import fixtureJSON from "../../../contracts/domain/parity-v1.json";
import { expect, test } from "vitest";
import { calculateSplits } from "./split-calculator";
import { computeBalances } from "./balance-engine";
import { deriveTripState } from "./trip-state-deriver";
import { toMinor } from "./money";
import { a, b, ledgerExpense } from "./test-support";
interface Fixture {
  version: number;
  splitCases: {
    name: string;
    total: string;
    currency: string;
    participants: string[];
    expected: string[];
  }[];
  balanceCases: {
    name: string;
    currency: string;
    total: string;
    payments: {
      person: string;
      amount: string;
    }[];
    splits: {
      person: string;
      amount: string;
    }[];
    expected: {
      for: string;
      with: string;
      amount: string;
    }[];
  }[];
  tripStateCases: {
    name: string;
    lastActivity: string;
    now: string;
    hasBalance: boolean;
    expected: string;
  }[];
}
const fixture = fixtureJSON as Fixture;
test("fixture version", () => expect(fixture.version).toBe(1));
for (const f of fixture.splitCases)
  test("equalSplits: " + f.name, () =>
    expect(
      calculateSplits({
        totalAmount: f.total,
        currency: f.currency,
        participants: f.participants,
        splitType: "equal",
      }).map((s) => s.amountOwed),
    ).toEqual(f.expected.map((x) => toMinor(x, f.currency))),
  );
for (const f of fixture.balanceCases)
  test("balances: " + f.name, () => {
    const r = computeBalances([
      ledgerExpense(
        Object.fromEntries(f.payments.map((p) => [p.person, p.amount])),
        Object.fromEntries(f.splits.map((p) => [p.person, p.amount])),
        f.currency,
        f.total,
      ),
    ]);
    expect(r).toHaveLength(f.expected.length * 2);
    for (const row of f.expected) {
      expect(
        r.find((r) => r.forUser === row.for && r.withUser === row.with)?.amount,
      ).toBe(toMinor(row.amount, f.currency));
      expect(
        r.find((r) => r.forUser === row.with && r.withUser === row.for)?.amount,
      ).toBe(-toMinor(row.amount, f.currency));
    }
  });
for (const f of fixture.tripStateCases)
  test("tripStates: " + f.name, () =>
    expect(
      deriveTripState(
        f.hasBalance
          ? [
              {
                forUser: a,
                withUser: b,
                currency: "GBP",
                amount: 1n,
              },
            ]
          : [],
        f.lastActivity,
        f.now,
      ),
    ).toBe(f.expected),
  );
