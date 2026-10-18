import { expect, test } from "vitest";
import { tripCard } from "./trip-presenter";
import { a, b, tripRows, addExpense, rowSettlement } from "./test-support";
test("trip card statuses distinguish empty, owed, owing, mixed and completed", () => {
  const now = "2026-05-23T12:00:00Z",
    empty = tripRows();
  expect(tripCard(empty, a, now).status).toEqual({ type: "empty", text: "" });
  let r = addExpense(empty, "1", { [a]: "30" }, { [a]: "15", [b]: "15" });
  expect(tripCard(r, a, now).status).toEqual({
    type: "owed",
    text: "you're owed €15.00",
  });
  expect(tripCard(r, b, now).status).toEqual({
    type: "owe",
    text: "you owe €15.00",
  });
  r = addExpense(r, "2", { [b]: "10" }, { [a]: "10" }, "10", "GBP");
  expect(tripCard(r, a, now).status).toEqual({
    type: "mixed",
    text: "net +€15.00 -£10.00",
  });
  const settled = rowSettlement(
    addExpense(empty, "1", { [a]: "30" }, { [a]: "15", [b]: "15" }),
    b,
    a,
    "15",
  );
  expect(tripCard(settled, a, now).status.text).toBe("all settled");
  expect(tripCard(settled, a, "2026-07-01T00:00:00Z").status.text).toBe(
    "settled · May 2026",
  );
});
test("trip cards use user names for avatar initials and active-member sorting", () => {
  const r = tripRows();
  const card = tripCard(r, b, "2026-05-23T00:00:00Z", "Rithwik");
  expect(card.members[0]).toMatchObject({
    id: b,
    displayName: "You",
    initial: "R",
  });
  expect(
    tripCard(
      {
        ...r,
        people: r.people.map((p) =>
          p.id === a ? { ...p, removed_at: "2026-05-23T00:00:00Z" } : p,
        ),
      },
      b,
      "2026-05-23T00:00:00Z",
    ).members.some((m) => m.id === a),
  ).toBe(false);
});
