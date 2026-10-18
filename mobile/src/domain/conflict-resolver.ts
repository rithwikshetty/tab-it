import type { SyncFields } from "./records";
export interface Versioned<T> {
  value: T;
  updatedAt: string;
  deletedAt: string | null;
  writeID: string;
}
export type WriteStamp = Omit<Versioned<unknown>, "value">;
export type MergeDecision = "keepLocal" | "applyRemote";
export function timestampUnits(value: string): bigint {
  const match = /\.(\d+)(?=Z|[+-]\d\d:\d\d$)/i.exec(value);
  const instant = match ? value.replace("." + match[1], "") : value;
  return (
    BigInt(Date.parse(instant)) * 1000000n +
    BigInt((match?.[1] ?? "").padEnd(9, "0").slice(0, 9) || "0")
  );
}
export function resolveConflict<T extends WriteStamp>(a: T, b: T): T {
  if (a.deletedAt !== null && b.deletedAt === null) return a;
  if (a.deletedAt === null && b.deletedAt !== null) return b;
  const at = timestampUnits(a.deletedAt ?? a.updatedAt),
    bt = timestampUnits(b.deletedAt ?? b.updatedAt);
  if (at !== bt) return at > bt ? a : b;
  return a.writeID.toLowerCase() >= b.writeID.toLowerCase() ? a : b;
}
export function mergeDecision(
  local: WriteStamp,
  localIsDirty: boolean,
  remote: WriteStamp,
): MergeDecision {
  if (local.writeID.toLowerCase() === remote.writeID.toLowerCase())
    return "keepLocal";
  if (!localIsDirty) return "applyRemote";
  return resolveConflict(local, remote).writeID === remote.writeID
    ? "applyRemote"
    : "keepLocal";
}
export function rowMergeDecision(
  local: SyncFields & {
    deleted_at?: string | null;
  },
  localIsDirty: boolean,
  remote: SyncFields & {
    deleted_at?: string | null;
  },
): MergeDecision {
  const stamp = (r: typeof local): WriteStamp => ({
    updatedAt: r.updated_at,
    deletedAt: r.deleted_at ?? null,
    writeID: r.write_id,
  });
  return mergeDecision(stamp(local), localIsDirty, stamp(remote));
}
export const ConflictResolver = {
  resolve: resolveConflict,
  merge: mergeDecision,
};
