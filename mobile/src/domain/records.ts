// Row shapes shared by the local store, the sync engine and the domain logic.
// Field names and value formats match the Supabase columns exactly, so a pulled
// row is stored as-is and a pushed row needs no mapping.
//
// Formats:
// - ids are lowercase UUID strings
// - timestamps are ISO-8601 strings (timestamptz)
// - dates are `YYYY-MM-DD` strings (date)
// - money is a plain decimal string normalised to the currency's minor-unit
//   scale with insignificant trailing zeros removed ("12.5", "1000", "1.234");
//   see `money.ts` for conversion to exact
//   integer minor units

export type UUID = string;
export type ISODateTime = string;
export type ISODate = string;
export type DecimalString = string;

export interface SyncFields {
  updated_at: ISODateTime;
  write_id: UUID;
}

export interface Profile extends SyncFields {
  id: UUID;
  display_name: string;
  avatar_url: string | null;
  created_at: ISODateTime;
}

export type TripKind = "trip" | "non_group";

export interface Trip extends SyncFields {
  id: UUID;
  name: string;
  kind: TripKind;
  member_signature: string | null;
  created_by: UUID;
  last_activity_at: ISODateTime;
  created_at: ISODateTime;
  deleted_at: ISODateTime | null;
}

export interface TripPerson extends SyncFields {
  id: UUID;
  trip_id: UUID;
  user_id: UUID | null;
  email: string;
  display_name: string;
  invited_by: UUID | null;
  joined_at: ISODateTime | null;
  removed_at: ISODateTime | null;
  created_at: ISODateTime;
}

export interface Category extends SyncFields {
  id: UUID;
  trip_id: UUID | null;
  name: string;
  icon: string;
  is_default: boolean;
  created_at: ISODateTime;
  deleted_at: ISODateTime | null;
}

export type PaymentMethod = "cash" | "card" | "bank_transfer";

export interface Expense extends SyncFields {
  id: UUID;
  trip_id: UUID;
  amount: DecimalString;
  currency: string;
  category_id: UUID | null;
  description: string;
  expense_date: ISODate;
  receipt_storage_path: string | null;
  payment_method: PaymentMethod;
  created_by: UUID;
  last_edited_by: UUID | null;
  created_at: ISODateTime;
  deleted_at: ISODateTime | null;
}

export type SplitType = "equal" | "exact" | "percentage" | "shares" | "adjustment";

export interface ExpensePayment extends SyncFields {
  expense_id: UUID;
  trip_person_id: UUID;
  amount_paid: DecimalString;
  payment_mode: SplitType;
  created_at: ISODateTime;
}

export interface ExpenseSplit extends SyncFields {
  expense_id: UUID;
  trip_person_id: UUID;
  amount_owed: DecimalString;
  split_type: SplitType;
  share_units: DecimalString | null;
  percentage: DecimalString | null;
  created_at: ISODateTime;
}

export interface Settlement extends SyncFields {
  id: UUID;
  trip_id: UUID;
  from_person_id: UUID;
  to_person_id: UUID;
  amount: DecimalString;
  currency: string;
  note: string | null;
  settled_at: ISODateTime;
  created_by: UUID;
  created_at: ISODateTime;
  deleted_at: ISODateTime | null;
}

export type ActivityAction =
  | "expense_created"
  | "expense_updated"
  | "expense_deleted"
  | "settlement_created"
  | "settlement_updated"
  | "settlement_deleted"
  | "member_joined"
  | "member_left"
  | "trip_created"
  | "trip_updated";

export interface ActivityLogEntry {
  id: UUID;
  trip_id: UUID;
  actor_id: UUID;
  action: ActivityAction;
  entity_type: "expense" | "settlement" | "trip" | "member";
  entity_id: UUID;
  timestamp: ISODateTime;
  snapshot_json: Record<string, unknown> | null;
}

export interface TripMutePref extends SyncFields {
  trip_id: UUID;
  user_id: UUID;
  muted_at: ISODateTime;
  created_at: ISODateTime;
}
