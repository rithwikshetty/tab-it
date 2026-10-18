import type {
  ActivityLogEntry,
  Category,
  Expense,
  ExpensePayment,
  ExpenseSplit,
  Profile,
  Settlement,
  Trip,
  TripMutePref,
  TripPerson,
} from "@/domain/records";

import { isDirty, rowKey, type Op, type State, type TableName, type Tables } from "./schema";
import { compareTimestamps, maxTimestamp, toMicros } from "./timestamps";

// Applies pulled server rows to the local store under the server's conflict
// policy (see `set_sync_fields`): delete wins, otherwise the later updated_at
// (or deleted_at between two deletes) wins, and write_id breaks exact ties.
//
// A clean local row always takes the server version. A dirty local row (an
// edit not yet pushed) is kept when it would also win on the server, so
// offline edits survive pulls. When the server already holds the local
// write_id, the row is acknowledged instead of pushed again.

export type RemoteExpense = Expense & {
  expense_payments: ExpensePayment[];
  expense_splits: ExpenseSplit[];
};

/**
 * One pull's results. A table left undefined failed to load this cycle: its
 * rows are still unknown, so nothing is removed on its account.
 */
export interface RemoteSnapshot {
  profiles?: Profile[];
  trips?: Trip[];
  trip_people?: TripPerson[];
  categories?: Category[];
  expenses?: RemoteExpense[];
  settlements?: Settlement[];
  trip_mute_prefs?: TripMutePref[];
  activity_log?: ActivityLogEntry[];
}

export interface MergeContext {
  userId: string;
  now: Date;
  /** Normalises a decimal amount to the currency's minor-unit scale. */
  normalizeAmount: (amount: string, currency: string) => string;
  /** Limits removals to one trip when the pull only fetched that trip. */
  tripId?: string;
}

export const GONE = "This was deleted, or you no longer have access to it.";

/** Activity older than this is dropped locally. */
export const ACTIVITY_WINDOW_DAYS = 90;

interface Stamp {
  updated_at: string;
  write_id: string;
  deleted_at?: string | null;
}

export type Outcome = "remote" | "local" | "same";

/** Which side the server keeps when both versions of a row reach it. */
export function resolveConflict(local: Stamp, remote: Stamp): Outcome {
  if (local.write_id === remote.write_id) return "same";
  const ld = local.deleted_at ?? null;
  const rd = remote.deleted_at ?? null;
  if (rd && !ld) return "remote";
  if (ld && !rd) return "local";
  const cmp = ld && rd ? compareTimestamps(rd, ld) : compareTimestamps(remote.updated_at, local.updated_at);
  if (cmp !== 0) return cmp > 0 ? "remote" : "local";
  return remote.write_id > local.write_id ? "remote" : "local";
}

export function mergeRemote(state: State, remote: RemoteSnapshot, ctx: MergeContext): Op[] {
  const ops: Op[] = [];
  const t = state.tables;
  const inScope = (tripId: string | null | undefined) => !ctx.tripId || tripId === ctx.tripId;

  /** Merges one row; returns true when the local row now matches the server. */
  function mergeRow<K extends TableName>(
    table: K,
    incoming: Tables[K] & Stamp,
    extra?: (local: Tables[K] | undefined) => Partial<Tables[K]>,
  ): boolean {
    const key = rowKey(table, incoming);
    const local = t[table].get(key) as (Tables[K] & Stamp & { _pushed?: string | null }) | undefined;
    const accept = () => {
      ops.push({ table, row: { ...incoming, ...extra?.(local), _pushed: incoming.write_id, _error: null } } as Op);
      return true;
    };
    if (!local || !isDirty(local)) return accept();
    const outcome = resolveConflict(local, incoming);
    if (outcome === "remote") return accept();
    if (outcome === "same") {
      ops.push({ table, row: { ...local, _pushed: local.write_id, _error: null } } as Op);
      return true;
    }
    return false;
  }

  const removedTrips = new Set<string>();
  const removedExpenses = new Set<string>();

  /** A person an unsent expense or payment still names must stay so the edit stays whole. */
  function referencedByUnsent(personId: string): boolean {
    for (const r of [...t.expense_payments.values(), ...t.expense_splits.values()]) {
      if (r.trip_person_id !== personId) continue;
      const e = t.expenses.get(r.expense_id);
      if (e && isDirty(e) && !e.deleted_at) return true;
    }
    for (const s of t.settlements.values()) {
      if ((s.from_person_id === personId || s.to_person_id === personId) && isDirty(s) && !s.deleted_at) return true;
    }
    return false;
  }

  /**
   * A row the server no longer returns was deleted there or is no longer
   * visible to this account. A clean copy goes. An unsent edit stays, marked
   * so the user can see it and discard it, instead of vanishing silently; an
   * unsent delete has nothing left to do and goes too.
   */
  function vanish<K extends "trips" | "trip_people" | "categories" | "expenses" | "settlements">(table: K, key: string): boolean {
    const row = t[table].get(key) as (Tables[K] & { deleted_at?: string | null }) | undefined;
    if (!row) return false;
    const holdsUnsent =
      (table === "trips" &&
        [...t.expenses.values(), ...t.settlements.values()].some((r) => r.trip_id === key && isDirty(r) && !r.deleted_at)) ||
      (table === "trip_people" && referencedByUnsent(key));
    if ((isDirty(row) && !row.deleted_at) || holdsUnsent) {
      ops.push({ table, row: { ...row, _error: GONE } } as Op);
      return false;
    }
    ops.push({ table, key, remove: true });
    return true;
  }

  // Profiles
  if (remote.profiles) {
    const seen = new Set<string>();
    for (const p of remote.profiles) {
      seen.add(p.id);
      mergeRow("profiles", { ...p, _pushed: p.write_id } as Tables["profiles"]);
    }
    if (!ctx.tripId) {
      for (const [key, p] of t.profiles) {
        if (p._pushed !== null && !seen.has(key) && key !== ctx.userId && !isDirty(p)) ops.push({ table: "profiles", key, remove: true });
      }
    }
  }

  // Trips
  if (remote.trips) {
    const seen = new Set<string>();
    for (const trip of remote.trips) {
      seen.add(trip.id);
      const kept = !mergeRow("trips", { ...trip, _pushed: trip.write_id } as Tables["trips"]);
      if (kept) {
        // The server bumps last_activity_at from triggers; show it even
        // while a local rename or delete is still waiting to be pushed.
        const local = t.trips.get(trip.id)!;
        const latest = maxTimestamp(local.last_activity_at, trip.last_activity_at);
        if (latest !== local.last_activity_at) ops.push({ table: "trips", row: { ...local, last_activity_at: latest } });
      }
    }
    for (const [key, trip] of t.trips) {
      if (inScope(trip.id) && trip._pushed !== null && !seen.has(key) && vanish("trips", key)) removedTrips.add(key);
    }
  }

  // Trip people
  if (remote.trip_people) {
    const seen = new Set<string>();
    for (const person of remote.trip_people) {
      seen.add(person.id);
      mergeRow("trip_people", { ...person, _pushed: person.write_id } as Tables["trip_people"]);
    }
    for (const [key, person] of t.trip_people) {
      if (inScope(person.trip_id) && person._pushed !== null && !seen.has(key)) vanish("trip_people", key);
    }
  }

  // Categories (built-in defaults have no trip)
  if (remote.categories) {
    const seen = new Set<string>();
    for (const c of remote.categories) {
      seen.add(c.id);
      mergeRow("categories", { ...c, _pushed: c.write_id } as Tables["categories"]);
    }
    for (const [key, c] of t.categories) {
      if (c.trip_id !== null && inScope(c.trip_id) && c._pushed !== null && !seen.has(key)) vanish("categories", key);
    }
  }

  // Expenses with their payment and split ledgers. Both ledgers arrive
  // embedded in the expense row, so they always match the expense version.
  if (remote.expenses) {
    const seen = new Set<string>();
    for (const e of remote.expenses) {
      seen.add(e.id);
      const { expense_payments, expense_splits, ...row } = e;
      const expense: Expense = { ...row, amount: ctx.normalizeAmount(row.amount, row.currency) };
      const matches = mergeRow("expenses", { ...expense, _pushed: expense.write_id } as Tables["expenses"], (local) =>
        local?._receipt && local.receipt_storage_path === expense.receipt_storage_path
          ? { _receipt: local._receipt, _receiptFile: local._receiptFile ?? null }
          : { _receipt: null, _receiptFile: null },
      );
      if (!matches) continue;
      replaceLedger(
        "expense_payments",
        e.id,
        expense_payments.map((p) => ({ ...p, amount_paid: ctx.normalizeAmount(p.amount_paid, row.currency) })),
      );
      replaceLedger(
        "expense_splits",
        e.id,
        expense_splits.map((s) => ({ ...s, amount_owed: ctx.normalizeAmount(s.amount_owed, row.currency) })),
      );
    }
    for (const [key, e] of t.expenses) {
      if (inScope(e.trip_id) && e._pushed !== null && !seen.has(key) && vanish("expenses", key)) removedExpenses.add(key);
    }
  }

  function replaceLedger<K extends "expense_payments" | "expense_splits">(table: K, expenseId: string, rows: Tables[K][]) {
    const keep = new Set(rows.map((r) => rowKey(table, r)));
    for (const [key, r] of t[table]) {
      if (r.expense_id === expenseId && !keep.has(key)) ops.push({ table, key, remove: true });
    }
    for (const r of rows) ops.push({ table, row: r } as Op);
  }

  // Settlements
  if (remote.settlements) {
    const seen = new Set<string>();
    for (const s of remote.settlements) {
      seen.add(s.id);
      mergeRow("settlements", { ...s, amount: ctx.normalizeAmount(s.amount, s.currency), _pushed: s.write_id } as Tables["settlements"]);
    }
    for (const [key, s] of t.settlements) {
      if (inScope(s.trip_id) && s._pushed !== null && !seen.has(key)) vanish("settlements", key);
    }
  }

  // Mute preferences: a row on the server means the trip is muted.
  if (remote.trip_mute_prefs) {
    const seen = new Set<string>();
    for (const m of remote.trip_mute_prefs) {
      const key = `${m.trip_id}:${m.user_id}`;
      seen.add(key);
      mergeRow("trip_mute_prefs", { ...m, _deleted: false, _pushed: m.write_id } as Tables["trip_mute_prefs"]);
    }
    for (const [key, m] of t.trip_mute_prefs) {
      if (inScope(m.trip_id) && !isDirty(m) && !seen.has(key)) ops.push({ table: "trip_mute_prefs", key, remove: true });
    }
  }

  // Activity is append-only: add new entries and keep a bounded window.
  if (remote.activity_log) {
    for (const a of remote.activity_log) {
      if (!t.activity_log.has(a.id)) ops.push({ table: "activity_log", row: a });
    }
  }
  const cutoff = BigInt(ctx.now.getTime() - ACTIVITY_WINDOW_DAYS * 86_400_000) * 1000n;
  const liveTrips = remote.trips && !ctx.tripId ? new Set(remote.trips.map((x) => x.id)) : null;
  for (const [key, a] of t.activity_log) {
    if (toMicros(a.timestamp) < cutoff || removedTrips.has(a.trip_id) || (liveTrips && !liveTrips.has(a.trip_id))) {
      ops.push({ table: "activity_log", key, remove: true });
    }
  }

  // Children of removed trips and expenses go with them, including rows that
  // never reached the server.
  if (removedTrips.size > 0) {
    for (const table of ["trip_people", "expenses", "settlements", "trip_mute_prefs", "categories"] as const) {
      for (const [key, row] of t[table]) {
        const tripId = (row as { trip_id: string | null }).trip_id;
        if (tripId && removedTrips.has(tripId)) {
          ops.push({ table, key, remove: true });
          if (table === "expenses") removedExpenses.add(key);
        }
      }
    }
  }
  if (removedExpenses.size > 0) {
    for (const table of ["expense_payments", "expense_splits"] as const) {
      for (const [key, row] of t[table]) {
        if (removedExpenses.has(row.expense_id)) ops.push({ table, key, remove: true });
      }
    }
  }

  return ops;
}

/**
 * Replaces a person created on this phone with the server's row for the same
 * email. When the server kept an older row under another id, every payment,
 * split and settlement naming the local id moves to it, and the touched rows
 * are marked for another push.
 */
export function adoptServerPerson(state: State, localId: string, server: TripPerson, newId: () => string): Op[] {
  const t = state.tables;
  const ops: Op[] = [];
  if (server.id !== localId) ops.push({ table: "trip_people", key: localId, remove: true });
  ops.push({ table: "trip_people", row: { ...server, _pushed: server.write_id, _error: null } });
  if (server.id === localId) return ops;
  ops.push({ meta: `alias.person.${localId}`, value: server.id });

  const now = new Date().toISOString();
  const touched = new Set<string>();
  for (const table of ["expense_payments", "expense_splits"] as const) {
    for (const [key, row] of t[table]) {
      if (row.trip_person_id !== localId) continue;
      ops.push({ table, key, remove: true });
      ops.push({ table, row: { ...row, trip_person_id: server.id } } as Op);
      touched.add(row.expense_id);
    }
  }
  for (const id of touched) {
    const e = t.expenses.get(id);
    if (e) ops.push({ table: "expenses", row: { ...e, updated_at: now, write_id: newId() } });
  }
  for (const s of t.settlements.values()) {
    if (s.from_person_id !== localId && s.to_person_id !== localId) continue;
    ops.push({
      table: "settlements",
      row: {
        ...s,
        from_person_id: s.from_person_id === localId ? server.id : s.from_person_id,
        to_person_id: s.to_person_id === localId ? server.id : s.to_person_id,
        updated_at: now,
        write_id: newId(),
      },
    });
  }
  return ops;
}
