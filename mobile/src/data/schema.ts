// Shapes of the local store: server rows plus local-only bookkeeping fields.
//
// Local-only bookkeeping rides on the rows as underscore fields:
// - `_pushed`: the write_id the server last acknowledged, or null when the row
//   has never reached the server. A row is dirty while `_pushed !== write_id`.
// - `_error`: why the server last refused this row, shown to the user.
// - `_receipt`: "pending" while a receipt photo still needs uploading,
//   "failed" when the server refused the upload; `_receiptFile` names the
//   on-device photo waiting to go up.
// - `_deleted`: a pending hard delete (unmuting a trip removes its mute row).
// - `_readAt` / `_dismissedAt`: activity rows the user read or swiped away here.

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

export interface LocalMeta {
  _pushed: string | null;
  _error?: string | null;
}

export type LocalTrip = Trip & LocalMeta;
export type LocalPerson = TripPerson & LocalMeta;
export type LocalExpense = Expense & LocalMeta & { _receipt?: "pending" | "failed" | null; _receiptFile?: string | null };
export type LocalSettlement = Settlement & LocalMeta;
export type LocalMute = TripMutePref & LocalMeta & { _deleted?: boolean };
export type LocalProfile = Profile & LocalMeta;
export type LocalCategory = Category & LocalMeta;
/** Activity is read-only server data; read and dismissed marks are this phone's own. */
export type LocalActivity = ActivityLogEntry & { _readAt?: string | null; _dismissedAt?: string | null };

export interface Tables {
  profiles: LocalProfile;
  trips: LocalTrip;
  trip_people: LocalPerson;
  categories: LocalCategory;
  expenses: LocalExpense;
  expense_payments: ExpensePayment;
  expense_splits: ExpenseSplit;
  settlements: LocalSettlement;
  activity_log: LocalActivity;
  trip_mute_prefs: LocalMute;
}

export type TableName = keyof Tables;

export const TABLE_NAMES: readonly TableName[] = [
  "profiles",
  "trips",
  "trip_people",
  "categories",
  "expenses",
  "expense_payments",
  "expense_splits",
  "settlements",
  "activity_log",
  "trip_mute_prefs",
];

export type TableMaps = { readonly [K in TableName]: ReadonlyMap<string, Tables[K]> };

export interface State {
  readonly tables: TableMaps;
  readonly meta: ReadonlyMap<string, string>;
}

export type Op =
  | { [K in TableName]: { table: K; row: Tables[K] } }[TableName]
  | { table: TableName; key: string; remove: true }
  | { meta: string; value: string | null };

/** The primary key a row is stored under, matching the server's primary key. */
export function rowKey<K extends TableName>(table: K, row: Tables[K]): string {
  switch (table) {
    case "expense_payments":
    case "expense_splits": {
      const r = row as ExpensePayment | ExpenseSplit;
      return `${r.expense_id}:${r.trip_person_id}`;
    }
    case "trip_mute_prefs": {
      const r = row as TripMutePref;
      return `${r.trip_id}:${r.user_id}`;
    }
    default:
      return (row as { id: string }).id;
  }
}

export function isDirty(row: { write_id: string; _pushed?: string | null }): boolean {
  return row._pushed !== row.write_id;
}
