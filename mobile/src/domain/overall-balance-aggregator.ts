import type { UserBalance } from "./balance-engine";
import { compare } from "./decimal";
export type ClaimIdentity =
  | {
      type: "user";
      id: string;
    }
  | {
      type: "email";
      email: string;
    };
export function resolveIdentity(
  userID: string | null,
  email: string,
): ClaimIdentity {
  return userID
    ? { type: "user", id: userID.toLowerCase() }
    : { type: "email", email: email.toLowerCase() };
}
export function identityKey(identity: ClaimIdentity): string {
  return identity.type === "user"
    ? "u:" + identity.id.toLowerCase()
    : "e:" + identity.email;
}
export const ClaimIdentity = {
  resolve: resolveIdentity,
  canonicalKey: identityKey,
  user: (id: string): ClaimIdentity => ({ type: "user", id: id.toLowerCase() }),
  email: (email: string): ClaimIdentity => ({ type: "email", email }),
};
export interface ContainerBalances {
  containerID: string;
  balances: readonly UserBalance[];
}
export interface OverallBalance {
  forIdentity: ClaimIdentity;
  withIdentity: ClaimIdentity;
  currency: string;
  amount: bigint;
}
export interface SourceBalance {
  containerID: string;
  currency: string;
  amount: bigint;
}
export type IdentityMap = Readonly<Record<string, ClaimIdentity>>;
export function aggregateBalances(
  containers: readonly ContainerBalances[],
  identityMap: IdentityMap,
): OverallBalance[] {
  const sums = new Map<string, OverallBalance>();
  for (const container of containers)
    for (const row of container.balances) {
      const a = identityMap[row.forUser],
        b = identityMap[row.withUser];
      if (!a || !b || identityKey(a) >= identityKey(b)) continue;
      const key = JSON.stringify([
        identityKey(a),
        identityKey(b),
        row.currency,
      ]);
      sums.set(key, {
        forIdentity: a,
        withIdentity: b,
        currency: row.currency,
        amount: (sums.get(key)?.amount ?? 0n) + row.amount,
      });
    }
  return [...sums.values()]
    .filter((b) => b.amount !== 0n)
    .sort(
      (a, b) =>
        compare(identityKey(a.forIdentity), identityKey(b.forIdentity)) ||
        compare(identityKey(a.withIdentity), identityKey(b.withIdentity)) ||
        compare(a.currency, b.currency),
    )
    .flatMap((b) => [
      b,
      {
        ...b,
        forIdentity: b.withIdentity,
        withIdentity: b.forIdentity,
        amount: -b.amount,
      },
    ]);
}
export function balanceBreakdown(
  containers: readonly ContainerBalances[],
  identityMap: IdentityMap,
  forIdentity: ClaimIdentity,
  withIdentity: ClaimIdentity,
): SourceBalance[] {
  const a = identityKey(forIdentity),
    b = identityKey(withIdentity);
  if (a === b) return [];
  return containers
    .flatMap((container) => {
      const sums = new Map<string, bigint>();
      for (const row of container.balances)
        if (
          identityMap[row.forUser] &&
          identityMap[row.withUser] &&
          identityKey(identityMap[row.forUser]!) === a &&
          identityKey(identityMap[row.withUser]!) === b
        )
          sums.set(row.currency, (sums.get(row.currency) ?? 0n) + row.amount);
      return [...sums]
        .filter(([, amount]) => amount !== 0n)
        .map(([currency, amount]) => ({
          containerID: container.containerID,
          currency,
          amount,
        }));
    })
    .sort(
      (a, b) =>
        compare(a.containerID, b.containerID) ||
        compare(a.currency, b.currency),
    );
}
export const OverallBalanceAggregator = {
  aggregate: aggregateBalances,
  breakdown: balanceBreakdown,
};
