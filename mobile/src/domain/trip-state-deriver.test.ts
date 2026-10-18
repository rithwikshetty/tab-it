import { expect, test } from "vitest";
import { deriveTripState } from "./trip-state-deriver";
import { a, b } from "./test-support";
const now = "2023-11-14T22:13:20Z";
test.each([
  ["settledRecentActivity", 1, 0n, "active", 30 * 86400],
  ["settledStaleActivity", 31, 0n, "completed", 30 * 86400],
  ["settledExactBoundary", 30, 0n, "completed", 30 * 86400],
  ["settledJustUnderBoundary", 30 - 1 / 86400, 0n, "active", 30 * 86400],
  ["unsettledStale", 365, 5000n, "active", 30 * 86400],
  ["unsettledRecent", 0, -2500n, "active", 30 * 86400],
  ["onlyZeroBalances", 60, 0n, "completed", 30 * 86400],
  ["customThresholdCompleted", 8, 0n, "completed", 7 * 86400],
  ["customThresholdActive", 3, 0n, "active", 7 * 86400],
] as const)("%s", (_name, days, amount, expected, threshold) =>
  expect(
    deriveTripState(
      [
        {
          forUser: a,
          withUser: b,
          currency: "EUR",
          amount,
        },
      ],
      new Date(Date.parse(now) - days * 86400000).toISOString(),
      now,
      threshold,
    ),
  ).toBe(expected),
);
test("multiCurrencyAnyNonZero", () =>
  expect(
    deriveTripState(
      [
        {
          forUser: a,
          withUser: b,
          currency: "EUR",
          amount: 0n,
        },
        {
          forUser: a,
          withUser: b,
          currency: "USD",
          amount: 1000n,
        },
      ],
      new Date(Date.parse(now) - 100 * 86400000).toISOString(),
      now,
    ),
  ).toBe("active"));
