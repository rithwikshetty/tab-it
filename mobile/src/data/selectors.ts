import type { ActivityOptions, TripRows } from "@/domain";

import type { LocalPerson, LocalTrip, State } from "./schema";
import { isDirty } from "./schema";
import { META_ACTIVITY_SEEN } from "./sync";

// Derived views over the store that several screens share. Each takes the
// whole state; callers memoise on it.

export function liveTrips(state: State): LocalTrip[] {
  return [...state.tables.trips.values()].filter((t) => t.kind === "trip" && !t.deleted_at);
}

/** The signed-in user's person row in each trip they belong to. */
export function myPeopleByTrip(state: State, userId: string): Map<string, LocalPerson> {
  const map = new Map<string, LocalPerson>();
  for (const p of state.tables.trip_people.values()) {
    if (p.user_id === userId && !p.removed_at) map.set(p.trip_id, p);
  }
  return map;
}

export function peopleInTrip(state: State, tripId: string, { includeRemoved = false } = {}): LocalPerson[] {
  return [...state.tables.trip_people.values()].filter((p) => p.trip_id === tripId && (includeRemoved || !p.removed_at));
}

export function mutedTripIds(state: State, userId: string): Set<string> {
  const ids = new Set<string>();
  for (const m of state.tables.trip_mute_prefs.values()) if (m.user_id === userId && !m._deleted) ids.add(m.trip_id);
  return ids;
}

export function activityOptions(state: State, userId: string): ActivityOptions {
  const joinedAtByTrip: Record<string, string> = {};
  const myTripPersonIDs = new Set<string>();
  for (const p of state.tables.trip_people.values()) {
    if (p.user_id !== userId) continue;
    myTripPersonIDs.add(p.id);
    if (p.joined_at) joinedAtByTrip[p.trip_id] = p.joined_at;
  }
  const localState: Record<string, { readAt?: string | null; dismissedAt?: string | null }> = {};
  for (const a of state.tables.activity_log.values()) {
    if (a._readAt || a._dismissedAt) localState[a.id] = { readAt: a._readAt, dismissedAt: a._dismissedAt };
  }
  return {
    currentUserID: userId,
    localState,
    utcOffsetMinutes: (d: Date) => -d.getTimezoneOffset(),
    lastSeenAt: state.meta.get(META_ACTIVITY_SEEN) ?? null,
    mutedTripIDs: mutedTripIds(state, userId),
    myTripPersonIDs,
    joinedAtByTrip,
  };
}

export interface UnsyncedChange {
  table: "trips" | "expenses" | "settlements" | "trip_people";
  key: string;
  tripId: string;
  label: string;
  detail: string;
  error: string | null;
}

/** Local changes the server hasn't acknowledged, with the reason any were refused. */
export function unsyncedChanges(state: State): UnsyncedChange[] {
  const t = state.tables;
  const tripName = (id: string) => {
    const trip = t.trips.get(id);
    return trip?.kind === "non_group" ? "Non-group" : (trip?.name ?? "Trip");
  };
  const rows: UnsyncedChange[] = [];
  for (const trip of t.trips.values()) {
    if (trip.kind === "trip" && isDirty(trip)) {
      rows.push({
        table: "trips",
        key: trip.id,
        tripId: trip.id,
        label: trip.name,
        detail: trip.deleted_at ? "Delete trip" : trip._pushed ? "Trip changes" : "New trip",
        error: trip._error ?? null,
      });
    }
  }
  for (const p of t.trip_people.values()) {
    if (isDirty(p) && p.user_id === null)
      rows.push({
        table: "trip_people",
        key: p.id,
        tripId: p.trip_id,
        label: p.display_name,
        detail: `Person in ${tripName(p.trip_id)}`,
        error: p._error ?? null,
      });
  }
  for (const e of t.expenses.values()) {
    if (isDirty(e))
      rows.push({
        table: "expenses",
        key: e.id,
        tripId: e.trip_id,
        label: e.description,
        detail: `${e.deleted_at ? "Delete expense" : "Expense"} in ${tripName(e.trip_id)}`,
        error: e._error ?? null,
      });
  }
  for (const s of t.settlements.values()) {
    if (isDirty(s))
      rows.push({
        table: "settlements",
        key: s.id,
        tripId: s.trip_id,
        label: "Payment",
        detail: `${s.deleted_at ? "Delete payment" : "Payment"} in ${tripName(s.trip_id)}`,
        error: s._error ?? null,
      });
  }
  return rows;
}

interface TripIndexEntry {
  expenses: TripRows["expenses"][number][];
  payments: TripRows["payments"][number][];
  splits: TripRows["splits"][number][];
  settlements: TripRows["settlements"][number][];
  people: LocalPerson[];
}

const tripIndexCache = new WeakMap<State["tables"], Map<string, TripIndexEntry>>();

/** Every trip's rows grouped once per state, so per-trip views stay cheap. */
function tripIndex(state: State): Map<string, TripIndexEntry> {
  const cached = tripIndexCache.get(state.tables);
  if (cached) return cached;
  const t = state.tables;
  const index = new Map<string, TripIndexEntry>();
  const entry = (tripId: string) => {
    let e = index.get(tripId);
    if (!e) index.set(tripId, (e = { expenses: [], payments: [], splits: [], settlements: [], people: [] }));
    return e;
  };
  const expenseTrip = new Map<string, string>();
  for (const e of t.expenses.values()) {
    expenseTrip.set(e.id, e.trip_id);
    entry(e.trip_id).expenses.push(e);
  }
  for (const p of t.expense_payments.values()) {
    const tripId = expenseTrip.get(p.expense_id);
    if (tripId) entry(tripId).payments.push(p);
  }
  for (const sp of t.expense_splits.values()) {
    const tripId = expenseTrip.get(sp.expense_id);
    if (tripId) entry(tripId).splits.push(sp);
  }
  for (const st of t.settlements.values()) entry(st.trip_id).settlements.push(st);
  for (const p of t.trip_people.values()) entry(p.trip_id).people.push(p);
  tripIndexCache.set(state.tables, index);
  return index;
}

/** All rows of one trip in the shape the domain presenters take. */
export function tripRows(state: State, tripId: string): TripRows | null {
  const trip = state.tables.trips.get(tripId);
  if (!trip) return null;
  const e = tripIndex(state).get(tripId) ?? { expenses: [], payments: [], splits: [], settlements: [], people: [] };
  const categories = [...state.tables.categories.values()].filter((c) => !c.deleted_at && (c.is_default || c.trip_id === tripId));
  return { trip, ...e, categories };
}

export interface KnownPerson {
  email: string;
  displayName: string;
  userId: string | null;
}

/**
 * People you've shared a trip with, newest first, for pickers. Mirrors the
 * server's suggest_trip_people, but runs offline on the local store.
 */
export function knownPeople(state: State, userId: string, selfEmail: string | null): KnownPerson[] {
  const myTrips = new Set<string>();
  for (const p of state.tables.trip_people.values()) if (p.user_id === userId && p.joined_at && !p.removed_at) myTrips.add(p.trip_id);
  const byEmail = new Map<string, KnownPerson & { updated: string }>();
  for (const p of state.tables.trip_people.values()) {
    if (!myTrips.has(p.trip_id) || p.removed_at || p.user_id === userId || p.email === selfEmail || p.email.endsWith("@users.tab"))
      continue;
    const known = byEmail.get(p.email);
    if (!known || known.updated < p.updated_at)
      byEmail.set(p.email, { email: p.email, displayName: p.display_name, userId: p.user_id, updated: p.updated_at });
  }
  return [...byEmail.values()].sort((a, b) => a.displayName.localeCompare(b.displayName)).map(({ updated: _u, ...rest }) => rest);
}

/** Every live container (trips and hidden non-group ones) as presenter rows. */
export function allTripRows(state: State): TripRows[] {
  const out: TripRows[] = [];
  for (const trip of state.tables.trips.values()) {
    if (trip.deleted_at) continue;
    const rows = tripRows(state, trip.id);
    if (rows) out.push(rows);
  }
  return out;
}
