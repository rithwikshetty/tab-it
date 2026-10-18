import { describe, expect, test } from "vitest";
import {
  calculateSplits,
  equalPercentages,
  type SplitOptions,
} from "./split-calculator";
import { fromMinor, toMinor } from "./money";
import { a, b, c, d } from "./test-support";
const calc = (o: Partial<SplitOptions> = {}) =>
  calculateSplits({
    totalAmount: "100",
    currency: "EUR",
    participants: [a, b],
    splitType: "equal",
    ...o,
  });
const amounts = (o: Partial<SplitOptions>) =>
  calc(o).map((s) => fromMinor(s.amountOwed, o.currency ?? "EUR"));
describe("Swift SplitCalculatorTests", () => {
  test.each([
    ["equalEvenTwoWay", "30", "EUR", [a, b], ["15", "15"]],
    [
      "equalThreeWayWithRemainder",
      "10",
      "USD",
      [b, c, a],
      ["3.33", "3.33", "3.34"],
    ],
    ["equalDollarThreeWay", "1", "USD", [a, b, c], ["0.34", "0.33", "0.33"]],
    ["equalSingleParticipant", "50", "EUR", [a], ["50"]],
    ["equalZeroAmount", "0", "EUR", [a, b, c], ["0", "0", "0"]],
    [
      "equalTwoCentRemainder",
      "0.05",
      "USD",
      [a, b, c],
      ["0.02", "0.02", "0.01"],
    ],
    ["equalJPYUsesWholeUnits", "101", "JPY", [b, a], ["50", "51"]],
    ["equalKWDUsesThreeDecimals", "1.001", "KWD", [a, b], ["0.501", "0.5"]],
  ] as const)("%s", (_name, totalAmount, currency, participants, expected) => {
    const result = calc({ totalAmount, currency, participants });
    expect(result.map((s) => fromMinor(s.amountOwed, currency))).toEqual(
      expected,
    );
    expect(result.map((s) => s.participantID)).toEqual(participants);
    expect(result.every((s) => s.splitType === "equal")).toBe(true);
    expect(result.reduce((n, s) => n + s.amountOwed, 0n)).toBe(
      toMinor(totalAmount, currency),
    );
  });
  test.each<{
    name: string;
    o: Partial<SplitOptions>;
    code: string;
    details?: Record<string, string | number>;
  }>([
    {
      name: "equalEmptyParticipantsThrows",
      o: { participants: [] },
      code: "emptyParticipants",
    },
    {
      name: "equalRejectsInvalidCurrencyPrecision",
      o: { totalAmount: "10.25", currency: "JPY" },
      code: "amountHasTooManyFractionDigits",
      details: { currency: "JPY", maximumFractionDigits: 0 },
    },
    {
      name: "exactSumMismatchThrows",
      o: { splitType: "exact", exactAmounts: { [a]: "50", [b]: "30" } },
      code: "amountsDoNotSumToTotal",
      details: { expected: "100", actual: "80" },
    },
    {
      name: "exactMissingParticipantThrows",
      o: {
        participants: [a, b, c],
        splitType: "exact",
        exactAmounts: { [a]: "50", [b]: "50" },
      },
      code: "missingAmountForParticipant",
      details: { id: c },
    },
    {
      name: "exactExtraNonParticipantThrows",
      o: {
        splitType: "exact",
        exactAmounts: { [a]: "40", [b]: "30", [c]: "30" },
      },
      code: "extraAmountForNonParticipant",
      details: { id: c },
    },
    {
      name: "exactNilAmountsThrows",
      o: { splitType: "exact" },
      code: "exactAmountsRequired",
    },
    {
      name: "equalSplitDuplicateParticipantThrows",
      o: { participants: [a, a, b] },
      code: "duplicateParticipant",
      details: { id: a },
    },
    {
      name: "exactSplitDuplicateParticipantThrows",
      o: {
        participants: [a, a, b],
        splitType: "exact",
        exactAmounts: { [a]: "50", [b]: "50" },
      },
      code: "duplicateParticipant",
      details: { id: a },
    },
    {
      name: "sharesMissingDictionaryThrows",
      o: { splitType: "shares" },
      code: "sharesRequired",
    },
    {
      name: "sharesMissingParticipantThrows",
      o: { splitType: "shares", shares: { [a]: "1" } },
      code: "missingShareForParticipant",
      details: { id: b },
    },
    {
      name: "sharesExtraShareThrows",
      o: { splitType: "shares", shares: { [a]: "1", [b]: "1", [c]: "1" } },
      code: "extraShareForNonParticipant",
      details: { id: c },
    },
    {
      name: "sharesDuplicateParticipantThrows",
      o: {
        splitType: "shares",
        participants: [a, a, b],
        shares: { [a]: "1", [b]: "1" },
      },
      code: "duplicateParticipant",
      details: { id: a },
    },
    {
      name: "percentageSumMustBe100",
      o: { splitType: "percentage", percentages: { [a]: "50", [b]: "49" } },
      code: "percentagesDoNotSumTo100",
      details: { actual: "99" },
    },
  ])("$name", ({ o, code, details }) => {
    expect(() => calc(o)).toThrowError(
      expect.objectContaining({ code, ...(details ? { details } : {}) }),
    );
  });
  test("exactValid", () => {
    const r = calc({
      participants: [a, b, c],
      splitType: "exact",
      exactAmounts: { [a]: "40", [b]: "30", [c]: "30" },
    });
    expect(r.map((s) => s.amountOwed)).toEqual([4000n, 3000n, 3000n]);
    expect(r.every((s) => s.splitType === "exact")).toBe(true);
  });
  test.each(["percentage", "shares", "adjustment"] as const)(
    "unsupportedTypes %s",
    (splitType) =>
      expect(() => calc({ participants: [a], splitType })).toThrow(),
  );
  test.each([
    [
      "sharesWholeProportional",
      "30",
      "EUR",
      [a, b],
      { [a]: "2", [b]: "1" },
      ["20", "10"],
    ],
    [
      "sharesFractional",
      "30",
      "GBP",
      [a, b, c, d],
      {
        [a]: "1",
        [b]: "1",
        [c]: "0.5",
        [d]: "0.5",
      },
      ["10", "10", "5", "5"],
    ],
    [
      "sharesRemainderLargestFraction",
      "100",
      "USD",
      [a, b],
      { [a]: "1", [b]: "2" },
      ["33.33", "66.67"],
    ],
    [
      "sharesTieBreakLowestUUID",
      "10",
      "USD",
      [b, c, a],
      { [a]: "1", [b]: "1", [c]: "1" },
      ["3.33", "3.33", "3.34"],
    ],
    [
      "sharesZeroDecimalCurrency",
      "100",
      "JPY",
      [a, b],
      { [a]: "1", [b]: "2" },
      ["33", "67"],
    ],
    ["sharesSingleParticipant", "12.34", "EUR", [a], { [a]: "0.5" }, ["12.34"]],
  ] as const)(
    "%s",
    (_name, totalAmount, currency, participants, shares, expected) => {
      const o = {
        totalAmount,
        currency,
        participants,
        shares,
        splitType: "shares" as const,
      };
      expect(amounts(o)).toEqual(expected);
      expect(calc(o).every((s) => s.splitType === "shares")).toBe(true);
    },
  );
  test("sharesCarriesWeights", () =>
    expect(
      calc({
        totalAmount: "30",
        splitType: "shares",
        shares: { [a]: "2", [b]: "1" },
      }).map((s) => s.shareUnits),
    ).toEqual(["2", "1"]));
  test("sharesSumPreserved", () => {
    const r = calc({
      totalAmount: "97.31",
      currency: "INR",
      participants: [a, b, c, d],
      splitType: "shares",
      shares: {
        [a]: "1.5",
        [b]: "0.5",
        [c]: "2.25",
        [d]: "0.75",
      },
    });
    expect(r.reduce((n, s) => n + s.amountOwed, 0n)).toBe(9731n);
  });
  test("sharesNonPositiveThrows", () => {
    for (const shares of [
      { [a]: "0", [b]: "1" },
      { [a]: "1", [b]: "-1" },
    ])
      expect(() => calc({ splitType: "shares", shares })).toThrowError(
        expect.objectContaining({
          code: "nonPositiveShare",
          details: { id: shares[a] === "0" ? a : b },
        }),
      );
  });
  test("percentageWholeProportional", () => {
    const r = calc({
      totalAmount: "80",
      splitType: "percentage",
      percentages: { [a]: "75", [b]: "25" },
    });
    expect(r.map((s) => s.amountOwed)).toEqual([6000n, 2000n]);
    expect(r.every((s) => s.splitType === "percentage")).toBe(true);
  });
  test("percentageCarriesValues", () => {
    const r = calc({
      totalAmount: "80",
      splitType: "percentage",
      percentages: { [a]: "12.5", [b]: "87.5" },
    });
    expect(r.map((s) => s.percentage)).toEqual(["12.5", "87.5"]);
    expect(r.every((s) => s.shareUnits === null)).toBe(true);
  });
  test("percentageRemainderDeterministic", () =>
    expect(
      amounts({
        participants: [a, b, c],
        splitType: "percentage",
        percentages: { [a]: "33.33", [b]: "33.33", [c]: "33.34" },
      }),
    ).toEqual(["33.33", "33.33", "33.34"]));
  test("percentageValidationThrows", () => {
    for (const [percentages, code] of [
      [undefined, "percentagesRequired"],
      [{ [a]: "100" }, "missingPercentageForParticipant"],
      [{ [a]: "50", [b]: "50", [c]: "1" }, "extraPercentageForNonParticipant"],
      [{ [a]: "0", [b]: "100" }, "nonPositivePercentage"],
    ] as const)
      expect(() => calc({ splitType: "percentage", percentages })).toThrowError(
        expect.objectContaining({ code }),
      );
  });
  test("equalPercentagesSeed", () => {
    expect(equalPercentages([b, c, a])).toEqual({
      [a]: "33.34",
      [b]: "33.33",
      [c]: "33.33",
    });
    expect(equalPercentages([a, b])).toEqual({ [a]: "50", [b]: "50" });
    expect(equalPercentages([])).toEqual({});
  });
  test("negative equal amounts follow Swift floor, not Kotlin truncation", () =>
    expect(
      amounts({
        totalAmount: "-0.05",
        participants: [c, a, b],
        currency: "USD",
      }),
    ).toEqual(["-0.02", "-0.01", "-0.02"]));
  test("very large weights retain exact rational ordering", () => {
    const r = calc({
      totalAmount: "999999999999.99",
      splitType: "shares",
      shares: {
        [a]: "99999999999999999999999999999999999999",
        [b]: "0.00000001",
      },
    });
    expect(r.reduce((n, s) => n + s.amountOwed, 0n)).toBe(99999999999999n);
  });
});
