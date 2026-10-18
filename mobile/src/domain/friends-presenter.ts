import { compareNames } from "./presentation-helpers";
import { timestampUnits } from "./conflict-resolver";
import type { TripRows } from "./models";
import type {
  ClaimIdentity,
  OverallBalance,
} from "./overall-balance-aggregator";
import {
  identityKey,
  resolveIdentity,
  aggregateBalances,
  balanceBreakdown,
} from "./overall-balance-aggregator";
import { balancesFromRows } from "./balance-engine";
import { mirroredSimplifiedBalances } from "./debt-simplifier";
import { abs, compare } from "./decimal";
import {
  avatarInitial,
  avatarTone,
  emailAvatarTone,
} from "./presentation-helpers";
import { formatMoney } from "./money-formatter";
import { timelineDays } from "./timeline-presenter";
import type { CalendarOptions } from "./expense-dates";
export type FriendIdentity = ClaimIdentity;
export function friendTone(claim: ClaimIdentity) {
  return claim.type === "user"
    ? avatarTone(claim.id)
    : emailAvatarTone(claim.email);
}
function friendsContext(trips: readonly TripRows[], currentUserID: string) {
  const me = resolveIdentity(currentUserID, ""),
    myKey = identityKey(me);
  const active = trips.filter(
    (t) =>
      !t.trip.deleted_at &&
      t.people.some(
        (p) => identityKey(resolveIdentity(p.user_id, p.email)) === myKey,
      ),
  );
  const identityMap: Record<string, ClaimIdentity> = {},
    activeClaims = new Map<string, ClaimIdentity>();
  for (const t of active)
    for (const p of t.people) {
      const claim = resolveIdentity(p.user_id, p.email);
      identityMap[p.id] = claim;
      if (!p.removed_at) activeClaims.set(identityKey(claim), claim);
    }
  const containers = active.map((t) => ({
    containerID: t.trip.id,
    balances: mirroredSimplifiedBalances(balancesFromRows(t)),
  }));
  const overall = aggregateBalances(containers, identityMap);
  const displayName = (claim: ClaimIdentity) =>
    active
      .flatMap((t) => t.people)
      .find(
        (p) =>
          identityKey(resolveIdentity(p.user_id, p.email)) ===
            identityKey(claim) && p.display_name.trim(),
      )?.display_name ?? (claim.type === "email" ? claim.email : "Member");
  const personID = (trip: TripRows, claim: ClaimIdentity) =>
    trip.people.find(
      (p) =>
        identityKey(resolveIdentity(p.user_id, p.email)) === identityKey(claim),
    )?.id;
  const sourceName = (trip: TripRows) =>
    trip.trip.kind === "non_group" ? "Non-group" : trip.trip.name;
  const sourceSummary = (claim: ClaimIdentity) => {
    const shared = active.filter((t) =>
        t.people.some(
          (p) =>
            identityKey(resolveIdentity(p.user_id, p.email)) ===
            identityKey(claim),
        ),
      ),
      names = shared
        .filter((t) => t.trip.kind !== "non_group")
        .map((t) => t.trip.name),
      parts: string[] = [];
    if (shared.some((t) => t.trip.kind === "non_group"))
      parts.push("Non-group");
    if (names.length === 1) parts.push(names[0]!);
    else if (names.length > 1) parts.push(`${names.length} trips`);
    return parts.join(" + ");
  };
  return {
    me,
    myKey,
    active,
    identityMap,
    activeClaims,
    containers,
    overall,
    displayName,
    personID,
    sourceName,
    sourceSummary,
  };
}
function amountLines(balances: readonly OverallBalance[], locale: string) {
  return balances
    .filter((b) => b.amount !== 0n)
    .sort((a, b) => compare(a.currency, b.currency))
    .map((b) => ({
      id: b.currency,
      currency: b.currency,
      label: b.amount > 0n ? "owes you" : "you owe",
      amount: formatMoney(abs(b.amount), b.currency, locale),
      isPositive: b.amount > 0n,
    }));
}
export function friendsList(
  trips: readonly TripRows[],
  currentUserID: string,
  locale = "en-US",
) {
  const ctx = friendsContext(trips, currentUserID),
    mine = ctx.overall.filter((b) => identityKey(b.forIdentity) === ctx.myKey),
    claims = new Map(ctx.activeClaims);
  for (const b of mine)
    if (b.amount !== 0n)
      claims.set(identityKey(b.withIdentity), b.withIdentity);
  claims.delete(ctx.myKey);
  const rows = [...claims.values()]
    .map((friend) => {
      const lines = amountLines(
          mine.filter(
            (b) => identityKey(b.withIdentity) === identityKey(friend),
          ),
          locale,
        ),
        displayName = ctx.displayName(friend);
      return {
        id: identityKey(friend),
        friend,
        displayName,
        initial: avatarInitial(displayName),
        tone: friendTone(friend),
        isPending: friend.type === "email",
        subtitle: ctx.sourceSummary(friend),
        lines,
        isSettled: !lines.length,
      };
    })
    .sort((a, b) => compareNames(a.displayName, b.displayName));
  const currencies = [
    ...new Set(mine.filter((b) => b.amount !== 0n).map((b) => b.currency)),
  ].sort();
  const overall = currencies.map((currency) => ({
    id: currency,
    currency,
    youAreOwed: mine
      .filter((b) => b.currency === currency && b.amount > 0n)
      .reduce((n, b) => n + b.amount, 0n),
    youOwe: mine
      .filter((b) => b.currency === currency && b.amount < 0n)
      .reduce((n, b) => n - b.amount, 0n),
  }));
  return {
    overall,
    active: rows.filter((r) => !r.isSettled),
    settled: rows.filter((r) => r.isSettled),
    isEmpty: !rows.length,
  };
}
export function friendDetail(
  trips: readonly TripRows[],
  currentUserID: string,
  friend: FriendIdentity,
  options: CalendarOptions = {},
) {
  const ctx = friendsContext(trips, currentUserID),
    key = identityKey(friend),
    { locale = "en-US" } = options;
  if (key === ctx.myKey) return null;
  const overall = amountLines(
    ctx.overall.filter(
      (b) =>
        identityKey(b.forIdentity) === ctx.myKey &&
        identityKey(b.withIdentity) === key,
    ),
    locale,
  );
  const sources = balanceBreakdown(
    ctx.containers,
    ctx.identityMap,
    ctx.me,
    friend,
  ).flatMap((src) => {
    const trip = ctx.active.find((t) => t.trip.id === src.containerID);
    if (!trip) return [];
    const myPID = ctx.personID(trip, ctx.me),
      friendPID = ctx.personID(trip, friend);
    if (!myPID || !friendPID) return [];
    return [
      {
        id: src.containerID.toUpperCase() + src.currency,
        containerID: src.containerID,
        sourceName: ctx.sourceName(trip),
        isNonGroup: trip.trip.kind === "non_group",
        currency: src.currency,
        label: src.amount > 0n ? "owes you" : "you owe",
        amount: formatMoney(abs(src.amount), src.currency, locale),
        isPositive: src.amount > 0n,
        suggestion: {
          fromPersonID: src.amount > 0n ? friendPID : myPID,
          toPersonID: src.amount > 0n ? myPID : friendPID,
          amount: abs(src.amount),
          currency: src.currency,
        },
      },
    ];
  });
  const days = ctx.active.flatMap((trip) => {
    const myPID = ctx.personID(trip, ctx.me),
      friendPID = ctx.personID(trip, friend);
    if (!myPID || !friendPID) return [];
    const expenses = trip.expenses.filter((e) => {
      const parties = new Set([
        ...trip.payments
          .filter((p) => p.expense_id === e.id)
          .map((p) => p.trip_person_id),
        ...trip.splits
          .filter((s) => s.expense_id === e.id)
          .map((s) => s.trip_person_id),
      ]);
      return parties.has(myPID) && parties.has(friendPID);
    });
    const settlements = trip.settlements.filter(
      (s) =>
        (s.from_person_id === myPID && s.to_person_id === friendPID) ||
        (s.from_person_id === friendPID && s.to_person_id === myPID),
    );
    return timelineDays(
      { ...trip, expenses, settlements },
      trip.people,
      [],
      myPID,
      options,
    ).map((day) => ({ ...day, trip, sourceName: ctx.sourceName(trip) }));
  });
  const timeline = [...new Set(days.map((d) => d.id))]
    .sort()
    .reverse()
    .map((id) => {
      const group = days.filter((d) => d.id === id);
      const entries = group
        .flatMap((d) =>
          d.items.map((item) => ({
            id: item.id,
            sourceName: d.sourceName,
            item:
              item.type === "expense"
                ? {
                    ...item,
                    expense: { ...item.expense, sourceName: d.sourceName },
                  }
                : {
                    ...item,
                    settlement: {
                      ...item.settlement,
                      sourceName: d.sourceName,
                    },
                  },
            created:
              d.trip.expenses.find((e) => e.id === item.id)?.created_at ??
              d.trip.settlements.find((s) => s.id === item.id)?.created_at ??
              "",
          })),
        )
        .sort((a, b) =>
          compare(timestampUnits(b.created), timestampUnits(a.created)),
        )
        .map(({ created: _created, ...entry }) => entry);
      return { id, dateLabel: group[0]!.dateLabel, entries };
    });
  const displayName = ctx.displayName(friend);
  return {
    friend,
    displayName,
    initial: avatarInitial(displayName),
    tone: friendTone(friend),
    isPending: friend.type === "email",
    overall,
    sources,
    timeline,
  };
}
export const FriendsPresenter = {
  list: friendsList,
  detail: friendDetail,
  tone: friendTone,
};
