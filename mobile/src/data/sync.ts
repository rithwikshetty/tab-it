import * as Network from "expo-network";
import { AppState } from "react-native";

import { normalizedAmount } from "@/domain";
import { uuid } from "@/lib/ids";
import { supabase } from "@/lib/supabase";

import type { TripPerson } from "@/domain/records";

import { adoptServerPerson, GONE, mergeRemote } from "./merge";
import { compareTimestamps } from "./timestamps";
import { call, fetchSnapshot, RemoteError, toRemoteError } from "./remote";
import { uploadPendingReceipts } from "./receipts";
import { isDirty, type LocalExpense, type LocalSettlement, type LocalTrip, type Op, type State } from "./schema";
import type { Store } from "./store";

// One engine keeps the local store and Supabase in step. Local edits commit to
// the store first and mark rows dirty; the engine pushes dirty rows, then
// pulls the server's view and merges it back. Runs are serialised and
// coalesced, so a burst of triggers (launch, foreground, network back,
// realtime, pull-to-refresh, local edits) costs one run. Transient failures
// back off and retry; rows the server refuses keep their error so the UI can
// show it, and are retried on the next run.

export type SyncPhase = "idle" | "syncing" | "offline" | "error";

export interface SyncStatus {
  phase: SyncPhase;
  /** Rows with local changes the server hasn't acknowledged. */
  pending: number;
  /** Rows the server refused on the last attempt. */
  failed: number;
  lastSyncedAt: Date | null;
  message: string | null;
}

export const META_ACTIVITY_SEEN = "activity.seenAt";
export const META_ACTIVITY_SEEN_PUSHED = "activity.seenAtPushed";

type PushTable = "trips" | "expenses" | "settlements" | "trip_mute_prefs" | "profiles" | "trip_people";

const RETRY_DELAYS = [2_000, 5_000, 15_000, 30_000, 60_000];
const POLL_INTERVAL = 5 * 60_000;

export class SyncEngine {
  private status: SyncStatus = { phase: "idle", pending: 0, failed: 0, lastSyncedAt: null, message: null };
  private listeners = new Set<() => void>();
  private running = false;
  private wantPush = false;
  private wantPull = false;
  private tripPulls = new Set<string>();
  private pushTimer: ReturnType<typeof setTimeout> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryAttempt = 0;
  private disposers: (() => void)[] = [];
  private stopped = false;

  constructor(
    private readonly store: Store,
    private readonly user: { id: string; email: string | null; displayName: string },
  ) {}

  start() {
    this.disposers.push(
      this.store.subscribe(() => {
        // Rows the server already refused wait for the next full run rather
        // than being retried on every unrelated change.
        if (this.refreshCounts() > 0) this.schedulePush();
      }),
    );
    // Other trips only update in the background through pulls, so pull
    // regularly while the app is open.
    const poll = setInterval(() => {
      if (AppState.currentState === "active") void this.request({ pull: true });
    }, POLL_INTERVAL);
    this.disposers.push(() => clearInterval(poll));
    const appState = AppState.addEventListener("change", (s) => {
      if (s === "active") this.request({ pull: true });
    });
    this.disposers.push(() => appState.remove());
    const network = Network.addNetworkStateListener((s) => {
      if (s.isConnected && s.isInternetReachable !== false && this.status.phase === "offline") {
        this.request({ pull: true });
      }
    });
    this.disposers.push(() => network.remove());
    this.refreshCounts();
    this.request({ pull: true });
  }

  stop() {
    this.stopped = true;
    for (const dispose of this.disposers) dispose();
    this.disposers = [];
    if (this.pushTimer) clearTimeout(this.pushTimer);
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.listeners.clear();
  }

  getStatus = (): SyncStatus => this.status;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /** Pushes local changes and, when asked, pulls the server's state. */
  request(options: { pull?: boolean; tripId?: string } = {}): Promise<void> {
    this.wantPush = true;
    if (options.tripId) this.tripPulls.add(options.tripId);
    else if (options.pull) this.wantPull = true;
    return this.run();
  }

  /** Runs everything now and resolves when done (pull-to-refresh). */
  refresh(): Promise<void> {
    this.retryAttempt = 0;
    return this.request({ pull: true });
  }

  private schedulePush() {
    if (this.pushTimer || this.stopped) return;
    this.pushTimer = setTimeout(() => {
      this.pushTimer = null;
      void this.request();
    }, 400);
  }

  private currentRun: Promise<void> | null = null;

  private run(): Promise<void> {
    if (this.running) return this.currentRun!;
    this.running = true;
    this.currentRun = (async () => {
      try {
        while (!this.stopped && (this.wantPush || this.wantPull || this.tripPulls.size > 0)) {
          this.setStatus({ phase: "syncing" });
          const pull = this.wantPull;
          const trips = [...this.tripPulls];
          this.wantPush = false;
          this.wantPull = false;
          this.tripPulls.clear();
          await this.push();
          if (pull) await this.pull();
          else for (const tripId of trips) await this.pull(tripId);
        }
        this.retryAttempt = 0;
        this.refreshCounts();
        this.setStatus({
          phase: this.status.failed > 0 ? "error" : "idle",
          lastSyncedAt: new Date(),
          message: this.status.failed > 0 ? failedMessage(this.status.failed) : null,
        });
      } catch (error) {
        const e = toRemoteError(error);
        this.refreshCounts();
        if (e.transient) {
          this.setStatus({
            phase: "offline",
            message: "You're offline. Changes are saved on this phone and will sync when you reconnect.",
          });
          this.scheduleRetry();
        } else {
          this.setStatus({ phase: "error", message: e.message });
        }
      } finally {
        this.running = false;
        this.currentRun = null;
      }
    })();
    return this.currentRun;
  }

  private scheduleRetry() {
    if (this.retryTimer || this.stopped) return;
    const delay = RETRY_DELAYS[Math.min(this.retryAttempt, RETRY_DELAYS.length - 1)]!;
    this.retryAttempt += 1;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      if (AppState.currentState === "active") void this.request({ pull: true });
    }, delay);
  }

  /** Updates the pending and failed counts; returns how many changes are ready to push. */
  private refreshCounts(): number {
    const s = this.store.getState().tables;
    let pending = 0;
    let failed = 0;
    for (const table of [s.trips, s.expenses, s.settlements, s.trip_mute_prefs, s.profiles, s.trip_people] as const) {
      for (const row of table.values() as Iterable<{ write_id: string; _pushed: string | null; _error?: string | null }>) {
        if (isDirty(row)) {
          pending += 1;
          if (row._error) failed += 1;
        }
      }
    }
    for (const e of s.expenses.values()) if (e._receipt === "pending" && !isDirty(e)) pending += 1;
    const meta = this.store.getState().meta;
    const cursorWaiting = meta.has(META_ACTIVITY_SEEN) && meta.get(META_ACTIVITY_SEEN) !== meta.get(META_ACTIVITY_SEEN_PUSHED);
    if (pending !== this.status.pending || failed !== this.status.failed) this.setStatus({ pending, failed });
    return pending - failed + (cursorWaiting ? 1 : 0);
  }

  private setStatus(patch: Partial<SyncStatus>) {
    this.status = { ...this.status, ...patch };
    for (const listener of this.listeners) listener();
  }

  // MARK: pull

  private async pull(tripId?: string) {
    // A full pull first claims trip people pending under this account's email,
    // so a trip someone added you to arrives with this pull. A failed claim
    // waits for the next full pull; the snapshot below reports being offline.
    if (!tripId) await call(supabase.rpc("claim_trip_people_for_current_email")).catch(() => null);
    if (this.stopped) return;
    const [{ snapshot, errors }, cursor] = await Promise.all([
      fetchSnapshot(tripId),
      tripId ? Promise.resolve(null) : call(supabase.rpc("activity_read_cursor")).catch(() => null),
    ]);
    // Signed out (or switched account) while the request was in flight.
    if (this.stopped) return;
    const ops = mergeRemote(this.store.getState(), snapshot, {
      userId: this.user.id,
      now: new Date(),
      normalizeAmount: normalizedAmount,
      tripId,
    });
    if (typeof cursor === "string") ops.push(...this.seenCursorOps(cursor));
    await this.store.commit(ops);
    const fatal = errors.find((e) => e.transient) ?? errors[0];
    if (fatal) throw fatal;
  }

  private seenCursorOps(serverSeenAt: string): Op[] {
    const local = this.store.getState().meta.get(META_ACTIVITY_SEEN);
    if (local && compareTimestamps(local, serverSeenAt) >= 0) return [];
    return [
      { meta: META_ACTIVITY_SEEN, value: serverSeenAt },
      { meta: META_ACTIVITY_SEEN_PUSHED, value: serverSeenAt },
    ];
  }

  // MARK: push

  private get state(): State {
    return this.store.getState();
  }

  /** Marks the version that was sent as acknowledged on the row as it is now. */
  private async ack<T extends PushTable>(table: T, key: string, writeId: string, patch: Record<string, unknown> = {}) {
    const row = this.state.tables[table].get(key);
    if (!row || this.stopped) return;
    await this.store.commit([{ table, row: { ...row, ...patch, _pushed: writeId, _error: null } } as Op]);
  }

  private async reject(table: PushTable, key: string, error: RemoteError) {
    const row = this.state.tables[table].get(key);
    if (!row || this.stopped) return;
    await this.store.commit([{ table, row: { ...row, _error: error.message } } as Op]);
  }

  /** Runs one row's push; a refused row is marked, a network failure stops the run. */
  private async attempt(table: PushTable, key: string, work: () => Promise<void>) {
    if (this.stopped) throw new RemoteError("Signed out", true);
    try {
      await work();
    } catch (error) {
      const e = toRemoteError(error);
      if (e.transient) throw e;
      console.warn(`[sync] ${table} ${key} refused: ${e.message}`);
      await this.reject(table, key, e);
    }
  }

  /** Stops a run that outlived its session, before it touches the server again. */
  private alive() {
    if (this.stopped) throw new RemoteError("Signed out", true);
  }

  private async push() {
    for (const step of [
      () => this.pushProfile(),
      () => this.pushTrips(),
      () => this.pushPeople(),
      () => this.pushExpenses(),
      () => this.pushSettlements(),
      () => uploadPendingReceipts(this.store, () => this.alive()),
      () => this.pushMutes(),
      () => this.pushActivitySeen(),
    ]) {
      this.alive();
      await step();
    }
  }

  /**
   * Updates one row and confirms the server wrote it. Row-level security makes
   * an update the user may no longer perform affect zero rows without an
   * error; that must not count as saved.
   */
  private async updateOne(table: "trips" | "expenses" | "settlements", id: string, values: Record<string, unknown>) {
    this.alive();
    const rows = (await call(
      (supabase.from(table) as unknown as { update: (v: unknown) => { eq: (c: string, v: string) => { select: (c: string) => never } } })
        .update(values)
        .eq("id", id)
        .select("id"),
    )) as { id: string }[] | null;
    if (!rows || rows.length === 0) throw new RemoteError(GONE, false);
  }

  /**
   * Deletes a row the server may or may not have (an unacknowledged create).
   * Matching no row means it never arrived. A refusal throws, so the delete
   * stays on this phone with its error rather than being forgotten.
   */
  private async deleteIfPresent(
    table: "trips" | "expenses" | "settlements",
    id: string,
    deletedAt: string,
    updatedAt: string,
    writeId: string,
  ) {
    this.alive();
    await call(supabase.from(table).update({ deleted_at: deletedAt, updated_at: updatedAt, write_id: writeId }).eq("id", id));
  }

  private async pushProfile() {
    const profile = this.state.tables.profiles.get(this.user.id);
    if (!profile || !isDirty(profile)) return;
    const writeId = profile.write_id;
    await this.attempt("profiles", profile.id, async () => {
      await call(
        supabase.rpc("ensure_current_profile", {
          p_display_name: profile.display_name,
          p_avatar_url: profile.avatar_url ?? undefined,
        }),
      );
      await this.ack("profiles", profile.id, writeId);
    });
  }

  private async pushTrips() {
    const trips = [...this.state.tables.trips.values()].filter((t) => t.kind === "trip" && isDirty(t));
    for (const trip of trips) {
      if (trip._pushed === null && trip.deleted_at) {
        // Deleted before the server acknowledged it. Its creation may still
        // have landed, so send the delete too, then forget it here.
        await this.attempt("trips", trip.id, async () => {
          await this.deleteIfPresent("trips", trip.id, trip.deleted_at!, trip.updated_at, trip.write_id);
          await this.store.commit(this.removeTripOps(trip.id));
        });
        continue;
      }
      await this.attempt("trips", trip.id, () => this.pushTrip(trip));
    }
  }

  private async pushTrip(trip: LocalTrip) {
    const writeId = trip.write_id;
    if (trip._pushed === null) {
      const creator = [...this.state.tables.trip_people.values()].find((p) => p.trip_id === trip.id && p.user_id === this.user.id);
      if (!creator) throw new RemoteError("The trip is missing its creator.", false);
      await call(
        supabase.rpc("create_trip_with_self", {
          p_trip_id: trip.id,
          p_person_id: creator.id,
          p_name: trip.name,
        }),
      );
      await this.ack("trip_people", creator.id, creator.write_id);
      // The RPC stamps its own write_id; a pull brings it down. Until then the
      // trip counts as pushed for the version that was sent.
      await this.ack("trips", trip.id, writeId);
      return;
    }
    await this.updateOne("trips", trip.id, {
      name: trip.name,
      deleted_at: trip.deleted_at,
      updated_at: trip.updated_at,
      write_id: writeId,
    });
    await this.ack("trips", trip.id, writeId);
  }

  private removeTripOps(tripId: string): Op[] {
    const t = this.state.tables;
    const ops: Op[] = [{ table: "trips", key: tripId, remove: true }];
    const expenseIds = new Set<string>();
    for (const [key, p] of t.trip_people) if (p.trip_id === tripId) ops.push({ table: "trip_people", key, remove: true });
    for (const [key, e] of t.expenses) {
      if (e.trip_id === tripId) {
        ops.push({ table: "expenses", key, remove: true });
        expenseIds.add(key);
      }
    }
    for (const [key, s] of t.settlements) if (s.trip_id === tripId) ops.push({ table: "settlements", key, remove: true });
    for (const table of ["expense_payments", "expense_splits"] as const) {
      for (const [key, r] of t[table]) if (expenseIds.has(r.expense_id)) ops.push({ table, key, remove: true });
    }
    return ops;
  }

  /**
   * People added on this phone. The server keys people by email within a
   * trip, so it may answer with an existing row under a different id; local
   * references then move to the server's id.
   */
  private async pushPeople() {
    const pending = [...this.state.tables.trip_people.values()].filter(
      (p) => p._pushed === null && p.user_id !== this.user.id && !p.removed_at,
    );
    for (const person of pending) {
      if (this.tripReady(person.trip_id) !== "ready") continue;
      await this.attempt("trip_people", person.id, async () => {
        const row = (await call(
          supabase.rpc("add_trip_person_by_email", {
            p_trip_id: person.trip_id,
            p_email: person.email,
            p_display_name: person.display_name,
            p_person_id: person.id,
          }),
        )) as unknown as TripPerson;
        this.alive();
        if (!this.state.tables.trip_people.has(person.id)) {
          // Removed here while the add was in flight: remove it on the server too.
          const removed = (await call(supabase.rpc("remove_trip_person", { p_person_id: row.id }))) as unknown as TripPerson;
          await this.store.commit([{ table: "trip_people", row: { ...removed, _pushed: removed.write_id, _error: null } }]);
          return;
        }
        await this.store.commit(adoptServerPerson(this.state, person.id, row, uuid));
      });
    }
  }

  /** Whether every person a ledger row names exists here and on the server. */
  private peopleReady(ids: Iterable<string>): boolean {
    const people = this.state.tables.trip_people;
    for (const id of ids) {
      const person = people.get(id);
      if (!person || person._pushed === null) return false;
    }
    return true;
  }

  /** A row can only be written once its trip exists on the server and is live. */
  private tripReady(tripId: string): "ready" | "waiting" | "deleted" {
    const trip = this.state.tables.trips.get(tripId);
    if (!trip) return "waiting";
    if (trip.deleted_at) return "deleted";
    if (trip.kind === "trip" && trip._pushed === null) return "waiting";
    return "ready";
  }

  private async pushExpenses() {
    const dirty = [...this.state.tables.expenses.values()].filter(isDirty);
    for (const expense of dirty) {
      const ready = this.tripReady(expense.trip_id);
      if (expense.deleted_at) {
        if (expense._pushed === null) {
          await this.attempt("expenses", expense.id, async () => {
            if (ready === "ready")
              await this.deleteIfPresent("expenses", expense.id, expense.deleted_at!, expense.updated_at, expense.write_id);
            await this.store.commit(this.removeExpenseOps(expense.id));
          });
        } else if (ready === "deleted") {
          // The trip's own delete carries it; the server refuses writes under a deleted trip.
          await this.ack("expenses", expense.id, expense.write_id);
        } else {
          await this.attempt("expenses", expense.id, async () => {
            await this.updateOne("expenses", expense.id, {
              deleted_at: expense.deleted_at,
              updated_at: expense.updated_at,
              write_id: expense.write_id,
            });
            await this.ack("expenses", expense.id, expense.write_id);
          });
        }
        continue;
      }
      if (ready !== "ready") continue;
      const t = this.state.tables;
      const named = [...t.expense_payments.values(), ...t.expense_splits.values()]
        .filter((r) => r.expense_id === expense.id)
        .map((r) => r.trip_person_id);
      if (!this.peopleReady(named)) continue;
      await this.attempt("expenses", expense.id, () => this.pushExpense(expense));
    }
  }

  private removeExpenseOps(expenseId: string): Op[] {
    const t = this.state.tables;
    const ops: Op[] = [{ table: "expenses", key: expenseId, remove: true }];
    for (const table of ["expense_payments", "expense_splits"] as const) {
      for (const [key, r] of t[table]) if (r.expense_id === expenseId) ops.push({ table, key, remove: true });
    }
    return ops;
  }

  private async pushExpense(expense: LocalExpense) {
    const t = this.state.tables;
    const payments = [...t.expense_payments.values()].filter((p) => p.expense_id === expense.id);
    const splits = [...t.expense_splits.values()].filter((s) => s.expense_id === expense.id);
    await call(
      supabase.rpc("create_expense_with_payments_and_splits", {
        p_expense: {
          id: expense.id,
          trip_id: expense.trip_id,
          amount: expense.amount,
          currency: expense.currency,
          category_id: expense.category_id,
          description: expense.description,
          expense_date: expense.expense_date,
          receipt_storage_path: expense.receipt_storage_path,
          payment_method: expense.payment_method,
          created_by: expense.created_by,
          last_edited_by: expense.last_edited_by,
          updated_at: expense.updated_at,
          write_id: expense.write_id,
        },
        p_payments: payments.map((p) => ({
          trip_person_id: p.trip_person_id,
          amount_paid: p.amount_paid,
          payment_mode: p.payment_mode,
          updated_at: p.updated_at,
          write_id: p.write_id,
        })),
        p_splits: splits.map((s) => ({
          trip_person_id: s.trip_person_id,
          amount_owed: s.amount_owed,
          split_type: s.split_type,
          share_units: s.share_units,
          percentage: s.percentage,
          updated_at: s.updated_at,
          write_id: s.write_id,
        })),
      }),
    );
    await this.ack("expenses", expense.id, expense.write_id);
  }

  private async pushSettlements() {
    const dirty = [...this.state.tables.settlements.values()].filter(isDirty);
    for (const s of dirty) {
      const ready = this.tripReady(s.trip_id);
      if (s.deleted_at && s._pushed === null) {
        await this.attempt("settlements", s.id, async () => {
          if (ready === "ready") await this.deleteIfPresent("settlements", s.id, s.deleted_at!, s.updated_at, s.write_id);
          await this.store.commit([{ table: "settlements", key: s.id, remove: true }]);
        });
        continue;
      }
      if (ready === "deleted" && s.deleted_at) {
        await this.ack("settlements", s.id, s.write_id);
        continue;
      }
      if (ready !== "ready" || !this.peopleReady([s.from_person_id, s.to_person_id])) continue;
      await this.attempt("settlements", s.id, () => this.pushSettlement(s));
    }
  }

  private async pushSettlement(s: LocalSettlement) {
    if (s.deleted_at) {
      await this.updateOne("settlements", s.id, { deleted_at: s.deleted_at, updated_at: s.updated_at, write_id: s.write_id });
    } else if (s._pushed !== null) {
      // An existing payment, possibly someone else's: insert policies require
      // created_by to be the current user, so edits go through UPDATE.
      await this.updateOne("settlements", s.id, {
        from_person_id: s.from_person_id,
        to_person_id: s.to_person_id,
        amount: s.amount,
        currency: s.currency,
        note: s.note,
        settled_at: s.settled_at,
        updated_at: s.updated_at,
        write_id: s.write_id,
      });
    } else {
      // A new payment. Upsert so a retry after a lost response doesn't fail.
      await call(
        supabase.from("settlements").upsert(
          {
            id: s.id,
            trip_id: s.trip_id,
            from_person_id: s.from_person_id,
            to_person_id: s.to_person_id,
            // Postgres reads the exact decimal string; the generated type says number.
            amount: s.amount as unknown as number,
            currency: s.currency,
            note: s.note,
            settled_at: s.settled_at,
            created_by: s.created_by,
            updated_at: s.updated_at,
            write_id: s.write_id,
          },
          { onConflict: "id" },
        ),
      );
    }
    await this.ack("settlements", s.id, s.write_id);
  }

  private async pushMutes() {
    const dirty = [...this.state.tables.trip_mute_prefs.values()].filter(isDirty);
    for (const m of dirty) {
      const key = `${m.trip_id}:${m.user_id}`;
      if (this.tripReady(m.trip_id) === "waiting") continue;
      await this.attempt("trip_mute_prefs", key, async () => {
        if (m._deleted) {
          await call(supabase.from("trip_mute_prefs").delete().eq("trip_id", m.trip_id).eq("user_id", m.user_id));
          const current = this.state.tables.trip_mute_prefs.get(key);
          if (current?.write_id === m.write_id) await this.store.commit([{ table: "trip_mute_prefs", key, remove: true }]);
        } else {
          await call(
            supabase
              .from("trip_mute_prefs")
              .upsert(
                { trip_id: m.trip_id, user_id: m.user_id, muted_at: m.muted_at, updated_at: m.updated_at, write_id: m.write_id },
                { onConflict: "trip_id,user_id" },
              ),
          );
          await this.ack("trip_mute_prefs", key, m.write_id);
        }
      });
    }
  }

  private async pushActivitySeen() {
    const meta = this.state.meta;
    const seen = meta.get(META_ACTIVITY_SEEN);
    if (!seen || seen === meta.get(META_ACTIVITY_SEEN_PUSHED)) return;
    this.alive();
    const serverSeenAt = await call(supabase.rpc("mark_activity_seen", { p_seen_at: seen }));
    this.alive();
    const ops: Op[] = [{ meta: META_ACTIVITY_SEEN_PUSHED, value: seen }];
    if (typeof serverSeenAt === "string" && compareTimestamps(serverSeenAt, seen) > 0) ops.push(...this.seenCursorOps(serverSeenAt));
    await this.store.commit(ops);
  }
}

function failedMessage(count: number): string {
  return count === 1 ? "1 change couldn't be saved to the server." : `${count} changes couldn't be saved to the server.`;
}
