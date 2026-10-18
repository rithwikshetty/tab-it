import { mapImportPeople, mapSplitwiseRows, normalizedEmail, type ImportResult } from "@/domain";
import type { ExpensePayment, ExpenseSplit, PaymentMethod, SplitType } from "@/domain/records";
import { nowISO, uuid } from "@/lib/ids";

import { discardStagedReceipt, receiptPath, stageReceipt } from "./receipts";
import type { LocalExpense, LocalMute, LocalPerson, LocalSettlement, LocalTrip, Op } from "./schema";
import type { UnsyncedChange } from "./selectors";
import type { CurrentUser } from "./session";
import { META_ACTIVITY_SEEN } from "./sync";
import type { Store } from "./store";

// Local-first writes. Each action commits to the store at once (the UI updates
// immediately and the change survives restarts) and leaves the row dirty for
// the sync engine to push. Server rules are mirrored here so a saved change
// never fails later for a reason the user could have been told about now.

export interface Ctx {
  store: Store;
  user: CurrentUser;
}

/**
 * People added offline can come back from the server under an existing id.
 * A form opened before that still holds the old id; this maps it forward.
 */
export const PERSON_ALIAS = "alias.person.";

function resolvePerson(store: Store, id: string): string {
  const meta = store.getState().meta;
  let current = id;
  for (let hops = 0; hops < 5; hops++) {
    const next = meta.get(PERSON_ALIAS + current);
    if (!next) break;
    current = next;
  }
  return current;
}

function stamp() {
  return { updated_at: nowISO(), write_id: uuid() };
}

// MARK: Trips

export async function createTrip({ store, user }: Ctx, name: string): Promise<string> {
  const trimmed = name.trim();
  if (!trimmed) throw new Error("Give the trip a name.");
  const now = nowISO();
  const tripId = uuid();
  const trip: LocalTrip = {
    id: tripId,
    name: trimmed.slice(0, 100),
    kind: "trip",
    member_signature: null,
    created_by: user.id,
    last_activity_at: now,
    created_at: now,
    deleted_at: null,
    ...stamp(),
    _pushed: null,
  };
  const profile = store.getState().tables.profiles.get(user.id);
  await store.commit([
    { table: "trips", row: trip },
    {
      table: "trip_people",
      row: {
        id: uuid(),
        trip_id: tripId,
        user_id: user.id,
        email: user.email ? normalizedEmail(user.email) : `${user.id}@users.tab`,
        display_name: (profile?.display_name ?? user.displayName).slice(0, 60),
        invited_by: user.id,
        joined_at: now,
        removed_at: null,
        created_at: now,
        ...stamp(),
        _pushed: null,
      },
    },
  ]);
  return tripId;
}

/**
 * Adds people to a trip by email. They're saved here at once and sent to the
 * server with the trip, so this works offline. An email already in the trip
 * is skipped, and a removed person is restored.
 */
export async function addPeople({ store, user }: Ctx, tripId: string, people: { email: string; displayName: string }[]) {
  const t = store.getState().tables;
  const inTrip = new Map([...t.trip_people.values()].filter((p) => p.trip_id === tripId).map((p) => [p.email, p]));
  const now = nowISO();
  const ops: Op[] = [];
  for (const person of people) {
    const email = normalizedEmail(person.email);
    const existing = inTrip.get(email);
    if (existing && !existing.removed_at) continue;
    if (existing) {
      // Re-adding a removed person goes through the server, which restores them.
      ops.push({ table: "trip_people", row: { ...existing, removed_at: null, ...stamp(), _pushed: null } });
      continue;
    }
    const row: LocalPerson = {
      id: uuid(),
      trip_id: tripId,
      user_id: null,
      email,
      display_name: (person.displayName.trim() || email.split("@")[0] || email).slice(0, 60),
      invited_by: user.id,
      joined_at: null,
      removed_at: null,
      created_at: now,
      ...stamp(),
      _pushed: null,
    };
    ops.push({ table: "trip_people", row });
    inTrip.set(email, row);
  }
  await store.commit(ops);
}

export async function renameTrip({ store }: Ctx, tripId: string, name: string) {
  const trip = store.getState().tables.trips.get(tripId);
  const trimmed = name.trim();
  if (!trip || !trimmed || trimmed === trip.name) return;
  await store.commit([{ table: "trips", row: { ...trip, name: trimmed.slice(0, 100), ...stamp(), _error: null } }]);
}

export async function deleteTrip({ store }: Ctx, tripId: string) {
  const trip = store.getState().tables.trips.get(tripId);
  if (!trip || trip.deleted_at) return;
  const s = stamp();
  await store.commit([{ table: "trips", row: { ...trip, deleted_at: s.updated_at, ...s, _error: null } }]);
}

// MARK: Expenses

export interface ExpenseInput {
  id?: string;
  tripId: string;
  amount: string;
  currency: string;
  categoryId: string | null;
  description: string;
  expenseDate: string;
  paymentMethod: PaymentMethod;
  payments: { personId: string; amount: string; mode: SplitType }[];
  splits: { personId: string; amount: string; type: SplitType; shareUnits?: string | null; percentage?: string | null }[];
  /** Leave the receipt as it is, remove it, or attach a new photo. */
  receipt?: { action: "keep" } | { action: "remove" } | { action: "set"; uri: string; width: number; height: number };
}

export async function saveExpense({ store, user }: Ctx, input: ExpenseInput): Promise<string> {
  if (input.id && store.getState().tables.expenses.get(input.id)?.deleted_at) throw new Error("This expense was deleted.");
  const id = input.id ?? uuid();
  const now = nowISO();
  const s = stamp();
  // Preparing a new photo is the only wait. Everything after it reads the store
  // as it is now, so a sync that ran meanwhile (say, renaming a person) isn't
  // undone by a stale copy.
  const newPath = receiptPath(input.tripId, id);
  const staged = input.receipt?.action === "set" ? await stageReceipt(input.receipt, newPath, s.write_id) : null;

  const t = store.getState().tables;
  const existing = t.expenses.get(id);
  if (existing?.deleted_at) {
    if (staged) discardStagedReceipt(newPath, staged);
    throw new Error("This expense was deleted.");
  }

  let receipt_storage_path = existing?.receipt_storage_path ?? null;
  let _receipt = existing?._receipt ?? null;
  let _receiptFile = existing?._receiptFile ?? null;
  // The local copy of a photo this save replaces or removes; it goes once the
  // save is on disk.
  const superseded =
    receipt_storage_path && (input.receipt?.action === "remove" || staged) ? { path: receipt_storage_path, file: _receiptFile } : null;
  if (input.receipt?.action === "remove") {
    receipt_storage_path = null;
    _receipt = null;
    _receiptFile = null;
  } else if (staged) {
    _receiptFile = staged;
    receipt_storage_path = newPath;
    _receipt = "pending";
  }

  const expense: LocalExpense = {
    id,
    trip_id: input.tripId,
    amount: input.amount,
    currency: input.currency,
    category_id: input.categoryId,
    description: input.description.trim().slice(0, 200),
    expense_date: input.expenseDate,
    receipt_storage_path,
    payment_method: input.paymentMethod,
    created_by: existing?.created_by ?? user.id,
    last_edited_by: existing ? user.id : null,
    created_at: existing?.created_at ?? now,
    deleted_at: null,
    ...s,
    _pushed: existing?._pushed ?? null,
    _error: null,
    _receipt,
    _receiptFile,
  };

  const ops: Op[] = [{ table: "expenses", row: expense }];
  for (const table of ["expense_payments", "expense_splits"] as const) {
    for (const [key, row] of t[table]) if (row.expense_id === id) ops.push({ table, key, remove: true });
  }
  for (const p of input.payments) {
    const row: ExpensePayment = {
      expense_id: id,
      trip_person_id: resolvePerson(store, p.personId),
      amount_paid: p.amount,
      payment_mode: p.mode,
      created_at: now,
      ...stamp(),
    };
    ops.push({ table: "expense_payments", row });
  }
  for (const sp of input.splits) {
    const row: ExpenseSplit = {
      expense_id: id,
      trip_person_id: resolvePerson(store, sp.personId),
      amount_owed: sp.amount,
      split_type: sp.type,
      share_units: sp.type === "shares" ? (sp.shareUnits ?? null) : null,
      percentage: sp.type === "percentage" ? (sp.percentage ?? null) : null,
      created_at: now,
      ...stamp(),
    };
    ops.push({ table: "expense_splits", row });
  }
  try {
    await store.commit(ops);
  } catch (error) {
    if (staged) discardStagedReceipt(newPath, staged);
    throw error;
  }
  if (superseded) discardStagedReceipt(superseded.path, superseded.file);
  return id;
}

export async function deleteExpense({ store }: Ctx, expenseId: string) {
  const expense = store.getState().tables.expenses.get(expenseId);
  if (!expense || expense.deleted_at) return;
  const s = stamp();
  await store.commit([{ table: "expenses", row: { ...expense, deleted_at: s.updated_at, ...s, _error: null } }]);
}

// MARK: Settlements

export interface SettlementInput {
  id?: string;
  tripId: string;
  fromPersonId: string;
  toPersonId: string;
  amount: string;
  currency: string;
  note: string | null;
  settledAt: string;
}

export async function saveSettlement({ store, user }: Ctx, input: SettlementInput): Promise<string> {
  if (input.fromPersonId === input.toPersonId) throw new Error("Pick two different people.");
  const existing = input.id ? store.getState().tables.settlements.get(input.id) : undefined;
  if (existing?.deleted_at) throw new Error("This payment was deleted.");
  const now = nowISO();
  const row: LocalSettlement = {
    id: existing?.id ?? input.id ?? uuid(),
    trip_id: input.tripId,
    from_person_id: resolvePerson(store, input.fromPersonId),
    to_person_id: resolvePerson(store, input.toPersonId),
    amount: input.amount,
    currency: input.currency,
    note: input.note?.trim() ? input.note.trim().slice(0, 200) : null,
    settled_at: input.settledAt,
    created_by: existing?.created_by ?? user.id,
    created_at: existing?.created_at ?? now,
    deleted_at: null,
    ...stamp(),
    _pushed: existing?._pushed ?? null,
    _error: null,
  };
  await store.commit([{ table: "settlements", row }]);
  return row.id;
}

export async function deleteSettlement({ store }: Ctx, settlementId: string) {
  const s0 = store.getState().tables.settlements.get(settlementId);
  if (!s0 || s0.deleted_at) return;
  const s = stamp();
  await store.commit([{ table: "settlements", row: { ...s0, deleted_at: s.updated_at, ...s, _error: null } }]);
}

// MARK: Preferences

export async function setTripMuted({ store, user }: Ctx, tripId: string, muted: boolean) {
  const key = `${tripId}:${user.id}`;
  const existing = store.getState().tables.trip_mute_prefs.get(key);
  if (!existing && !muted) return;
  const now = nowISO();
  const row: LocalMute = {
    trip_id: tripId,
    user_id: user.id,
    muted_at: muted ? now : (existing?.muted_at ?? now),
    created_at: existing?.created_at ?? now,
    ...stamp(),
    _pushed: existing?._pushed ?? null,
    _deleted: !muted,
  };
  await store.commit([{ table: "trip_mute_prefs", row }]);
}

export async function updateDisplayName({ store, user }: Ctx, name: string) {
  const trimmed = name.trim().slice(0, 60);
  if (!trimmed) throw new Error("Your name can't be empty.");
  const t = store.getState().tables;
  const profile = t.profiles.get(user.id);
  const now = nowISO();
  const ops: Op[] = [
    {
      table: "profiles",
      row: {
        id: user.id,
        avatar_url: profile?.avatar_url ?? null,
        created_at: profile?.created_at ?? now,
        display_name: trimmed,
        ...stamp(),
        _pushed: profile?._pushed ?? null,
      },
    },
  ];
  // The server copies a profile's name onto its trip people; show it at once.
  for (const p of t.trip_people.values()) {
    if (p.user_id === user.id && p.display_name !== trimmed) ops.push({ table: "trip_people", row: { ...p, display_name: trimmed } });
  }
  await store.commit(ops);
}

/** Moves the read cursor to now: every activity so far counts as read, here and on the server. */
export async function markActivitySeen({ store }: Ctx) {
  await store.commit([{ meta: META_ACTIVITY_SEEN, value: nowISO() }]);
}

export async function markActivityRead({ store }: Ctx, id: string, dismiss = false) {
  const row = store.getState().tables.activity_log.get(id);
  if (!row) return;
  const now = nowISO();
  await store.commit([{ table: "activity_log", row: { ...row, _readAt: row._readAt ?? now, ...(dismiss ? { _dismissedAt: now } : {}) } }]);
}

export function setPreference({ store }: Ctx, key: string, value: string | null) {
  return store.commit([{ meta: `pref.${key}`, value }]);
}

/**
 * Drops a local change the server refused or can no longer accept. A row that
 * never reached the server is deleted with its children; otherwise it's marked
 * acknowledged so the next pull restores the server's copy (or removes it).
 */
export async function discardLocalChange({ store }: Ctx, table: UnsyncedChange["table"], key: string) {
  const t = store.getState().tables;
  if (table === "receipts") {
    const e = t.expenses.get(key);
    if (!e) return;
    if (e.receipt_storage_path) discardStagedReceipt(e.receipt_storage_path, e._receiptFile);
    await store.commit([{ table: "expenses", row: { ...e, _receipt: null, _receiptFile: null } }]);
    return;
  }
  const row = t[table].get(key);
  if (!row) return;
  if (row._pushed !== null || table === "profiles" || table === "trip_mute_prefs") {
    if (table === "trip_mute_prefs" && row._pushed === null) {
      await store.commit([{ table, key, remove: true }]);
      return;
    }
    await store.commit([{ table, row: { ...row, _pushed: row.write_id, _error: null } } as Op]);
    return;
  }
  const ops: Op[] = [{ table, key, remove: true }];
  const expenseIds = new Set<string>(table === "expenses" ? [key] : []);
  if (table === "trips") {
    for (const [k, r] of t.expenses) if (r.trip_id === key) (ops.push({ table: "expenses", key: k, remove: true }), expenseIds.add(k));
    for (const [k, r] of t.settlements) if (r.trip_id === key) ops.push({ table: "settlements", key: k, remove: true });
    for (const [k, r] of t.trip_people) if (r.trip_id === key) ops.push({ table: "trip_people", key: k, remove: true });
  }
  for (const child of ["expense_payments", "expense_splits"] as const) {
    for (const [k, r] of t[child]) if (expenseIds.has(r.expense_id)) ops.push({ table: child, key: k, remove: true });
  }
  await store.commit(ops);
}

/**
 * Creates a trip from a parsed Splitwise export. Everyone except the chosen
 * "you" joins as a pending person with a placeholder email that can be
 * replaced later. It all lands locally in one commit and syncs like any other
 * change, so importing works offline.
 */
export async function importSplitwise(ctx: Ctx, parsed: ImportResult, tripName: string, selfPerson: string | null): Promise<string> {
  const tripId = await createTrip(ctx, tripName);
  const t = ctx.store.getState().tables;
  const creator = [...t.trip_people.values()].find((p) => p.trip_id === tripId && p.user_id === ctx.user.id)!;
  const now = nowISO();
  const { people, personIDs } = mapImportPeople({
    names: parsed.people,
    selfPerson,
    tripID: tripId,
    user: { id: ctx.user.id, email: ctx.user.email, displayName: creator.display_name },
    creatorPersonID: creator.id,
    newPersonIDs: Object.fromEntries(parsed.people.map((name) => [name, uuid()])),
    now,
    writeID: uuid(),
  });
  const rows = mapSplitwiseRows(parsed, {
    tripID: tripId,
    userID: ctx.user.id,
    personIDs,
    now,
    rowIDs: parsed.rows.map(() => uuid()),
    writeID: uuid(),
  });
  const ops: Op[] = [];
  for (const p of people) if (p.id !== creator.id) ops.push({ table: "trip_people", row: { ...p, ...stamp(), _pushed: null } });
  for (const e of rows.expenses) ops.push({ table: "expenses", row: { ...e, ...stamp(), _pushed: null } });
  for (const p of rows.payments) ops.push({ table: "expense_payments", row: p });
  for (const sp of rows.splits) ops.push({ table: "expense_splits", row: sp });
  for (const st of rows.settlements) ops.push({ table: "settlements", row: { ...st, ...stamp(), _pushed: null } });
  await ctx.store.commit(ops);
  return tripId;
}
