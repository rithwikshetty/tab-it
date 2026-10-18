import { normalizeDecimal } from "@/domain/decimal";
import { isSupportedCurrency } from "@/domain/currency-catalog";
import { decimalFromInput, normalizedAmount } from "@/domain/money";
import type { ActivityAction, ActivityLogEntry, PaymentMethod, SplitType, TripKind } from "@/domain/records";

import { resolveConflict } from "../merge";
import { rowKey, type Op, type State } from "../schema";
import { compareTimestamps, maxTimestamp } from "../timestamps";

export const LEGACY_TABLES = [
  "ZPROFILEENTITY", "ZTRIPENTITY", "ZTRIPPERSONENTITY", "ZCATEGORYENTITY",
  "ZEXPENSEENTITY", "ZPAYMENTENTITY", "ZEXPENSESPLITENTITY", "ZSETTLEMENTENTITY",
  "ZTRIPMUTEENTITY", "ZACTIVITYENTITY",
] as const;

export type LegacyTable = typeof LEGACY_TABLES[number];
export type LegacyValue = string | number | Uint8Array | null;
export type LegacyRow = Record<string, LegacyValue>;
export type LegacyRows = Record<LegacyTable, LegacyRow[]>;
export const IMPORT_MARKER = "legacy.swiftData.v1";
export const ACTIVITY_SEEN = "activity.seenAt";
const APPLE_EPOCH_MS = Date.UTC(2001, 0, 1);

export function legacyUUID(value: LegacyValue | undefined): string {
  const hex = value instanceof Uint8Array
    ? Array.from(value, (b) => b.toString(16).padStart(2, "0")).join("")
    : typeof value === "string" ? value.replace(/-/g, "").toLowerCase() : "";
  if (!/^[a-f0-9]{32}$/.test(hex)) throw new Error("Invalid legacy UUID");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function optionalUUID(value: LegacyValue | undefined): string | null {
  return value == null ? null : legacyUUID(value);
}

export function legacyTimestamp(value: LegacyValue | undefined): string {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new Error("Invalid legacy timestamp");
  const micros = Math.round(value * 1_000_000);
  if (!Number.isSafeInteger(micros)) throw new Error("Legacy timestamp is out of range");
  const seconds = Math.floor(micros / 1_000_000);
  const fraction = (micros - seconds * 1_000_000).toString().padStart(6, "0");
  return `${new Date(APPLE_EPOCH_MS + seconds * 1000).toISOString().slice(0, 19)}.${fraction}Z`;
}

function optionalTimestamp(value: LegacyValue | undefined): string | null {
  return value == null ? null : legacyTimestamp(value);
}

export function legacyDecimal(value: LegacyValue | undefined): string {
  if (typeof value !== "string") throw new Error("Legacy decimals must be selected as SQL text");
  const decimal = decimalFromInput(value);
  if (decimal === null || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value)) {
    throw new Error("Invalid legacy decimal");
  }
  return normalizeDecimal(decimal);
}

function optionalDecimal(value: LegacyValue | undefined): string | null {
  return value == null ? null : legacyDecimal(value);
}

function legacyMoney(value: LegacyValue | undefined, currency: string): string {
  const amount = legacyDecimal(value);
  return isSupportedCurrency(currency) ? normalizedAmount(amount, currency) : amount;
}

function text(row: LegacyRow, column: string): string {
  const value = row[column];
  if (typeof value !== "string") throw new Error(`Missing legacy ${column}`);
  return value;
}

function optionalText(row: LegacyRow, column: string): string | null {
  return row[column] == null ? null : text(row, column);
}

function choice<T extends string>(value: string, allowed: readonly T[]): T {
  if (!allowed.includes(value as T)) throw new Error("Unsupported legacy enum value");
  return value as T;
}

function stamp(row: LegacyRow) {
  return {
    updated_at: legacyTimestamp(row.ZUPDATEDAT),
    write_id: legacyUUID(row.ZWRITEID),
    _pushed: optionalUUID(row.ZPUSHEDWRITEID),
  };
}

function pk(row: LegacyRow, column = "Z_PK"): number {
  const value = row[column];
  if (typeof value !== "number" || !Number.isSafeInteger(value)) throw new Error(`Invalid legacy ${column}`);
  return value;
}

function referenced(rows: Map<number, LegacyRow>, row: LegacyRow, column: string): LegacyRow {
  const parent = rows.get(pk(row, column));
  if (!parent) throw new Error(`Missing legacy relationship ${column}`);
  return parent;
}

function snapshot(row: LegacyRow): ActivityLogEntry["snapshot_json"] {
  const data = row.ZSNAPSHOTDATA;
  if (data == null) return null;
  const parsed: unknown = JSON.parse(typeof data === "string" ? data : new TextDecoder().decode(data as Uint8Array));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Invalid legacy activity snapshot");
  return parsed as Record<string, unknown>;
}

export class LegacyAccountMismatch extends Error {}

export interface ConversionOptions {
  pendingReceiptPaths?: ReadonlySet<string>;
  pendingActivitySeenAt?: string | null;
  legacyUserId?: string;
}

export function convertLegacyRows(rows: LegacyRows, userId: string, options: ConversionOptions = {}): Op[] {
  userId = legacyUUID(userId);
  const profiles = rows.ZPROFILEENTITY;
  const cursorOwners = profiles.filter((r) => r.ZACTIVITYLASTSEENAT != null).map((r) => legacyUUID(r.ZID));
  const owner = options.legacyUserId ? legacyUUID(options.legacyUserId)
    : cursorOwners.length === 1 ? cursorOwners[0]
    : profiles.length === 1 ? legacyUUID(profiles[0]!.ZID) : null;
  const trips = new Map(rows.ZTRIPENTITY.map((r) => [pk(r), r]));
  const expenses = new Map(rows.ZEXPENSEENTITY.map((r) => [pk(r), r]));
  const memberTrips = new Set(rows.ZTRIPPERSONENTITY
    .filter((r) => optionalUUID(r.ZUSERID) === userId)
    .map((r) => pk(r, "ZTRIP")));
  if (owner !== userId || !profiles.some((r) => legacyUUID(r.ZID) === userId) ||
      [...trips].some(([key, r]) => legacyUUID(r.ZCREATEDBYID) !== userId && !memberTrips.has(key))) {
    throw new LegacyAccountMismatch("Legacy data does not match the signed-in account");
  }
  const ops: Op[] = [];
  for (const r of profiles) {
    ops.push({ table: "profiles", row: {
      id: legacyUUID(r.ZID), display_name: text(r, "ZDISPLAYNAME"), avatar_url: optionalText(r, "ZAVATARURL"),
      created_at: legacyTimestamp(r.ZUPDATEDAT), ...stamp(r),
    } });
  }
  for (const r of rows.ZTRIPENTITY) {
    ops.push({ table: "trips", row: {
      id: legacyUUID(r.ZID), name: text(r, "ZNAME"),
      kind: choice<TripKind>(r.ZKIND == null ? "trip" : text(r, "ZKIND"), ["trip", "non_group"]),
      member_signature: optionalText(r, "ZMEMBERSIGNATURE"), created_by: legacyUUID(r.ZCREATEDBYID),
      last_activity_at: legacyTimestamp(r.ZLASTACTIVITYAT), created_at: legacyTimestamp(r.ZCREATEDAT),
      deleted_at: optionalTimestamp(r.ZDELETEDAT), ...stamp(r),
    } });
  }
  for (const r of rows.ZTRIPPERSONENTITY) {
    ops.push({ table: "trip_people", row: {
      id: legacyUUID(r.ZID), trip_id: legacyUUID(referenced(trips, r, "ZTRIP").ZID),
      user_id: optionalUUID(r.ZUSERID), email: text(r, "ZEMAIL"), display_name: text(r, "ZDISPLAYNAME"),
      invited_by: optionalUUID(r.ZINVITEDBYID), joined_at: optionalTimestamp(r.ZJOINEDAT),
      removed_at: optionalTimestamp(r.ZREMOVEDAT), created_at: legacyTimestamp(r.ZCREATEDAT), ...stamp(r),
    } });
  }
  for (const r of rows.ZCATEGORYENTITY) {
    ops.push({ table: "categories", row: {
      id: legacyUUID(r.ZID), trip_id: optionalUUID(r.ZTRIPID), name: text(r, "ZNAME"), icon: text(r, "ZICON"),
      is_default: r.ZISDEFAULT === 1, created_at: legacyTimestamp(r.ZUPDATEDAT),
      deleted_at: optionalTimestamp(r.ZDELETEDAT), ...stamp(r),
    } });
  }
  for (const r of rows.ZEXPENSEENTITY) {
    const path = optionalText(r, "ZRECEIPTSTORAGEPATH");
    ops.push({ table: "expenses", row: {
      id: legacyUUID(r.ZID), trip_id: legacyUUID(referenced(trips, r, "ZTRIP").ZID),
      amount: legacyMoney(r.ZAMOUNT, text(r, "ZCURRENCY")), currency: text(r, "ZCURRENCY"), category_id: optionalUUID(r.ZCATEGORYID),
      description: text(r, "ZDESCRIPTIONTEXT"), expense_date: legacyTimestamp(r.ZEXPENSEDATE).slice(0, 10),
      receipt_storage_path: path,
      payment_method: choice<PaymentMethod>(text(r, "ZPAYMENTMETHODRAW"), ["cash", "card", "bank_transfer"]),
      created_by: legacyUUID(r.ZCREATEDBYID), last_edited_by: optionalUUID(r.ZLASTEDITEDBYID),
      created_at: legacyTimestamp(r.ZCREATEDAT), deleted_at: optionalTimestamp(r.ZDELETEDAT),
      ...stamp(r), ...(path && options.pendingReceiptPaths?.has(path) ? { _receipt: "pending" as const } : {}),
    } });
  }
  const splitTypes: readonly SplitType[] = ["equal", "exact", "percentage", "shares", "adjustment"];
  for (const r of rows.ZPAYMENTENTITY) {
    const expense = referenced(expenses, r, "ZEXPENSE");
    ops.push({ table: "expense_payments", row: {
      expense_id: legacyUUID(expense.ZID), trip_person_id: legacyUUID(r.ZTRIPPERSONID),
      amount_paid: legacyMoney(r.ZAMOUNTPAID, text(expense, "ZCURRENCY")), payment_mode: choice(text(r, "ZPAYMENTMODERAW"), splitTypes),
      created_at: legacyTimestamp(expense.ZCREATEDAT), updated_at: legacyTimestamp(r.ZUPDATEDAT), write_id: legacyUUID(r.ZWRITEID),
    } });
  }
  for (const r of rows.ZEXPENSESPLITENTITY) {
    const expense = referenced(expenses, r, "ZEXPENSE");
    ops.push({ table: "expense_splits", row: {
      expense_id: legacyUUID(expense.ZID), trip_person_id: legacyUUID(r.ZTRIPPERSONID),
      amount_owed: legacyMoney(r.ZAMOUNTOWED, text(expense, "ZCURRENCY")), split_type: choice(text(r, "ZSPLITTYPERAW"), splitTypes),
      share_units: optionalDecimal(r.ZSHAREUNITS), percentage: optionalDecimal(r.ZPERCENTAGE),
      created_at: legacyTimestamp(expense.ZCREATEDAT), updated_at: legacyTimestamp(r.ZUPDATEDAT), write_id: legacyUUID(r.ZWRITEID),
    } });
  }
  for (const r of rows.ZSETTLEMENTENTITY) {
    ops.push({ table: "settlements", row: {
      id: legacyUUID(r.ZID), trip_id: legacyUUID(referenced(trips, r, "ZTRIP").ZID),
      from_person_id: legacyUUID(r.ZFROMPERSONID), to_person_id: legacyUUID(r.ZTOPERSONID),
      amount: legacyMoney(r.ZAMOUNT, text(r, "ZCURRENCY")), currency: text(r, "ZCURRENCY"), note: optionalText(r, "ZNOTE"),
      settled_at: legacyTimestamp(r.ZSETTLEDAT), created_by: legacyUUID(r.ZCREATEDBYID),
      created_at: legacyTimestamp(r.ZCREATEDAT), deleted_at: optionalTimestamp(r.ZDELETEDAT), ...stamp(r),
    } });
  }
  for (const r of rows.ZTRIPMUTEENTITY) {
    ops.push({ table: "trip_mute_prefs", row: {
      trip_id: legacyUUID(r.ZTRIPID), user_id: userId, muted_at: legacyTimestamp(r.ZMUTEDAT),
      created_at: legacyTimestamp(r.ZMUTEDAT), ...stamp(r), _deleted: r.ZISMUTED === 0,
    } });
  }
  for (const r of rows.ZACTIVITYENTITY) {
    const id = legacyUUID(r.ZID);
    ops.push({ table: "activity_log", row: {
      id, trip_id: legacyUUID(r.ZTRIPID), actor_id: legacyUUID(r.ZACTORID),
      action: text(r, "ZACTION") as ActivityAction,
      entity_type: choice(text(r, "ZENTITYTYPE"), ["expense", "settlement", "trip", "member"]),
      entity_id: legacyUUID(r.ZENTITYID), timestamp: legacyTimestamp(r.ZTIMESTAMP), snapshot_json: snapshot(r),
      _readAt: optionalTimestamp(r.ZREADAT), _dismissedAt: optionalTimestamp(r.ZDISMISSEDAT),
    } });
  }
  const profile = profiles.find((r) => legacyUUID(r.ZID) === userId)!;
  const seen = [optionalTimestamp(profile.ZACTIVITYLASTSEENAT), options.pendingActivitySeenAt]
    .filter((v): v is string => !!v).sort(compareTimestamps).at(-1);
  if (seen) ops.push({ meta: ACTIVITY_SEEN, value: seen });
  return ops;
}

export function selectLegacyOps(state: State, incoming: readonly Op[]): Op[] {
  const keepExpenses = new Set<string>();
  const ops: Op[] = [];
  for (const op of incoming) {
    if ("meta" in op) {
      const existing = state.meta.get(op.meta);
      if (!existing || (op.meta === ACTIVITY_SEEN && op.value && compareTimestamps(op.value, existing) > 0)) ops.push(op);
      continue;
    }
    if (!("row" in op)) continue;
    if (op.table === "expense_payments" || op.table === "expense_splits") {
      if (keepExpenses.has(op.row.expense_id)) ops.push(op);
      continue;
    }
    const current = state.tables[op.table].get(rowKey(op.table, op.row as never));
    if (op.table === "activity_log" && current) {
      const activity = state.tables.activity_log.get(op.row.id)!;
      ops.push({ table: "activity_log", row: {
        ...op.row, ...activity,
        _readAt: later(activity._readAt, op.row._readAt),
        _dismissedAt: later(activity._dismissedAt, op.row._dismissedAt),
      } });
      continue;
    }
    if (current) {
      if (!("write_id" in current) || !("write_id" in op.row) || resolveConflict(current, op.row) !== "remote") continue;
    }
    if (op.table === "expenses") {
      keepExpenses.add(op.row.id);
      for (const table of ["expense_payments", "expense_splits"] as const) {
        for (const [key, row] of state.tables[table]) {
          if (row.expense_id === op.row.id) ops.push({ table, key, remove: true });
        }
      }
    }
    ops.push(op);
  }
  return ops;
}

function later(left: string | null | undefined, right: string | null | undefined): string | null {
  return left && right ? maxTimestamp(left, right) : left ?? right ?? null;
}
