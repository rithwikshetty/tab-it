import type { PostgrestError } from "@supabase/supabase-js";

import type {
  ActivityLogEntry,
  Category,
  Profile,
  Settlement,
  Trip,
  TripMutePref,
  TripPerson,
} from "@/domain/records";
import { supabase } from "@/lib/supabase";

import { ACTIVITY_WINDOW_DAYS, type RemoteExpense, type RemoteSnapshot } from "./merge";

// Thin, typed access to the Supabase contract. Every function either returns
// data or throws a RemoteError that says whether retrying later can help.

export class RemoteError extends Error {
  constructor(
    message: string,
    /** Network trouble or a server hiccup: retry later. */
    readonly transient: boolean,
    readonly code?: string,
  ) {
    super(message);
    this.name = "RemoteError";
  }
}

interface Result<T> {
  data: T | null;
  error: PostgrestError | null;
  status?: number;
}

const TRANSIENT_CODES = new Set(["PGRST301", "PGRST303", "57014", "40001", "40P01", "53300", "08006"]);

export function toRemoteError(error: unknown, status?: number): RemoteError {
  if (error instanceof RemoteError) return error;
  const e = error as Partial<PostgrestError> & { message?: string; name?: string };
  const message = e?.message ?? String(error);
  const code = e?.code || undefined;
  const network =
    !code &&
    (status === undefined || status === 0 || status >= 500 || status === 408 || status === 429 ||
      /network|fetch|timeout|abort|connection|offline/i.test(message));
  const transient = network || (code !== undefined && TRANSIENT_CODES.has(code)) || (status !== undefined && status >= 500);
  return new RemoteError(message, transient, code);
}

export async function call<T>(request: PromiseLike<Result<T>>): Promise<T> {
  let result: Result<T>;
  try {
    result = await request;
  } catch (error) {
    throw toRemoteError(error);
  }
  if (result.error) throw toRemoteError(result.error, result.status);
  return result.data as T;
}

const PAGE = 1000;

/**
 * Reads a whole table in pages keyed on `id` (keyset pagination): each page
 * starts after the last id seen, so rows inserted or deleted while paging
 * can't shift later pages and duplicate or hide rows.
 */
async function fetchAllById<T extends { id: string }>(query: () => Query): Promise<T[]> {
  const rows: T[] = [];
  let after: string | null = null;
  for (;;) {
    let q = query().order("id").limit(PAGE);
    if (after) q = q.gt("id", after);
    const batch = ((await call(q)) ?? []) as T[];
    rows.push(...batch);
    if (batch.length < PAGE) return rows;
    after = batch[batch.length - 1]!.id;
  }
}

/** Offset pages, for the composite-key mute table (a handful of rows per user). */
async function fetchAllByOffset<T>(query: () => Query): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const batch = ((await call(query().range(from, from + PAGE - 1))) ?? []) as T[];
    rows.push(...batch);
    if (batch.length < PAGE) return rows;
  }
}

// PostgREST returns numeric columns as JSON numbers, which JavaScript would
// parse into floats. Money columns are cast to text so amounts stay exact.
const PROFILE_COLUMNS = "id,display_name,avatar_url,created_at,updated_at,write_id";
const LEDGER_COLUMNS = "expense_id,trip_person_id,created_at,updated_at,write_id";
const EXPENSE_COLUMNS = [
  "id,trip_id,amount::text,currency,category_id,description,expense_date,receipt_storage_path,payment_method",
  "created_by,last_edited_by,created_at,updated_at,deleted_at,write_id",
  `expense_payments(${LEDGER_COLUMNS},amount_paid::text,payment_mode)`,
  `expense_splits(${LEDGER_COLUMNS},amount_owed::text,split_type,share_units::text,percentage::text)`,
].join(",");
const SETTLEMENT_COLUMNS =
  "id,trip_id,from_person_id,to_person_id,amount::text,currency,note,settled_at,created_by,created_at,updated_at,deleted_at,write_id";

// The generated client types can't follow these dynamic selects, so queries
// are built untyped and their rows typed by the caller.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Query = any;

function from(table: string, columns: string): Query {
  return (supabase.from as (t: string) => Query)(table).select(columns);
}

/**
 * Fetches everything the signed-in user can see, or just one trip. Tables
 * load in parallel; a table that fails is left out of the snapshot so the
 * merge treats its rows as unknown rather than deleted.
 */
export async function fetchSnapshot(tripId?: string): Promise<{ snapshot: RemoteSnapshot; errors: RemoteError[] }> {
  const scoped = (query: Query, column: string): Query => (tripId ? query.eq(column, tripId) : query);
  const activityCutoff = new Date(Date.now() - ACTIVITY_WINDOW_DAYS * 86_400_000).toISOString();

  const tasks: { [K in keyof RemoteSnapshot]-?: () => Promise<NonNullable<RemoteSnapshot[K]>> } = {
    profiles: () => fetchAllById<Profile>(() => from("visible_profiles", PROFILE_COLUMNS)),
    trips: () => fetchAllById<Trip>(() => scoped(from("trips", "*"), "id")),
    trip_people: () => fetchAllById<TripPerson>(() => scoped(from("trip_people", "*"), "trip_id")),
    categories: () => fetchAllById<Category>(() => from("categories", "*")),
    expenses: () => fetchAllById<RemoteExpense>(() => scoped(from("expenses", EXPENSE_COLUMNS), "trip_id")),
    settlements: () => fetchAllById<Settlement>(() => scoped(from("settlements", SETTLEMENT_COLUMNS), "trip_id")),
    trip_mute_prefs: () => fetchAllByOffset<TripMutePref>(() => from("trip_mute_prefs", "*").order("trip_id").order("user_id")),
    activity_log: () =>
      call<ActivityLogEntry[]>(
        scoped(from("activity_log", "*"), "trip_id").gte("timestamp", activityCutoff).order("timestamp", { ascending: false }).limit(300),
      ),
  };

  const names = (Object.keys(tasks) as (keyof RemoteSnapshot)[]).filter(
    (name) => !tripId || (name !== "categories" && name !== "trip_mute_prefs"),
  );
  const settled = await Promise.allSettled(names.map((name) => tasks[name]()));
  const snapshot: RemoteSnapshot = {};
  const errors: RemoteError[] = [];
  settled.forEach((result, i) => {
    const name = names[i]!;
    if (result.status === "fulfilled") (snapshot as Record<string, unknown>)[name] = result.value;
    else errors.push(toRemoteError(result.reason));
  });
  return { snapshot, errors };
}
