import { expect, test } from "vitest";
import { friendsList, friendDetail } from "./friends-presenter";
import { ClaimIdentity as I } from "./overall-balance-aggregator";
import { a, b, c, tripRows, person, addExpense } from "./test-support";
const goa = () =>
  addExpense(
    tripRows("goa", "Goa", [
      person("ag", "Me", "goa", a),
      person("bg", "Bob", "goa", b),
    ]),
    "hotel",
    { ag: "40" },
    { ag: "20", bg: "20" },
    "40",
    "GBP",
  );
const ng = () => {
  const r = addExpense(
    tripRows("ng", "", [
      person("an", "Me", "ng", a),
      person("bn", "Bob", "ng", b),
    ]),
    "drinks",
    { bn: "10" },
    { an: "5", bn: "5" },
    "10",
    "GBP",
  );
  return { ...r, trip: { ...r.trip, kind: "non_group" as const } };
};
const redirected = () => {
  const r = tripRows("red", "Redirected", [
    person("ag", "Me", "red", a),
    person("bg", "Bob", "red", b),
    person("cg", "Carol", "red", c),
  ]);
  return addExpense(
    addExpense(r, "bob", { bg: "20" }, { ag: "10", bg: "10" }, "20", "GBP"),
    "carol",
    { cg: "20" },
    { bg: "10", cg: "10" },
    "20",
    "GBP",
  );
};
test("netsAcrossContainers", () => {
  const s = friendsList([goa(), ng()], a);
  expect(s.active).toHaveLength(1);
  expect(s.active[0]).toMatchObject({
    displayName: "Bob",
    subtitle: "Non-group + Goa",
    lines: [{ currency: "GBP", isPositive: true, amount: "£15.00" }],
  });
});
test("excludesSelf", () => {
  const s = friendsList([goa()], a);
  expect([...s.active, ...s.settled].every((r) => r.id !== "u:" + a)).toBe(
    true,
  );
});
test("ignoresContainersWithoutCurrentUser", () => {
  const r = tripRows("other", "Other", [
    person("bo", "Bob", "other", b),
    person("co", "Carol", "other", c),
  ]);
  const s = friendsList([r], a);
  expect(s.active).toEqual([]);
  expect(s.settled).toEqual([]);
});
test("overallBanner", () =>
  expect(
    friendsList([goa(), ng()], a).overall.find((l) => l.currency === "GBP"),
  ).toMatchObject({ youAreOwed: 1500n, youOwe: 0n }));
test("detailSources", () => {
  const s = friendDetail([goa(), ng()], a, I.user(b))!;
  expect(s.displayName).toBe("Bob");
  expect(s.overall[0]?.isPositive).toBe(true);
  expect(s.sources).toHaveLength(2);
  expect(s.sources.find((s) => s.sourceName === "Goa")).toMatchObject({
    isPositive: true,
    amount: "£20.00",
  });
  expect(s.sources.find((s) => s.isNonGroup)).toMatchObject({
    sourceName: "Non-group",
    isPositive: false,
    amount: "£5.00",
  });
});
test("redirectedFriendBalance", () => {
  const t = redirected(),
    s = friendsList([t], a);
  expect(
    s.active.find((r) => r.displayName === "Carol")?.lines[0],
  ).toMatchObject({ isPositive: false, amount: "£10.00" });
  expect(friendDetail([t], a, I.user(c))?.sources[0]?.suggestion).toEqual({
    fromPersonID: "ag",
    toPersonID: "cg",
    amount: 1000n,
    currency: "GBP",
  });
});
test("detailTimeline", () => {
  const s = friendDetail([goa(), ng()], a, I.user(b))!;
  expect(
    new Set(s.timeline.flatMap((d) => d.entries.map((e) => e.sourceName))),
  ).toEqual(new Set(["Goa", "Non-group"]));
});
test("pendingFriend", () => {
  const people = [
      person("ac", "Me", "pending", a),
      {
        ...person("cp", "Carol", "pending", null),
        email: "carol@x.com",
        joined_at: null,
      },
    ],
    r = addExpense(
      tripRows("pending", "", people),
      "cab",
      { ac: "8" },
      { ac: "4", cp: "4" },
      "8",
      "GBP",
    );
  const p = friendsList([r], a).active[0]!;
  expect(p.displayName).toBe("Carol");
  expect(p.isPending).toBe(true);
  expect(p.friend).toEqual(I.email("carol@x.com"));
  expect(p.lines[0]?.isPositive).toBe(true);
});
test("removed settled members leave the friends list, outstanding members remain", () => {
  const r = goa(),
    people = r.people.map((p) =>
      p.user_id === b ? { ...p, removed_at: "2026-06-01T00:00:00Z" } : p,
    );
  expect(friendsList([{ ...r, people }], a).active).toHaveLength(1);
  expect(friendsList([{ ...r, people, expenses: [] }], a).isEmpty).toBe(true);
  expect(friendDetail([r], a, I.user(a))).toBeNull();
});
