import { describe, expect, test } from "vitest";
import { calculatePayments, type PaymentOptions } from "./payment-calculator";
import { a, b, c } from "./test-support";
import { fromMinor, toMinor } from "./money";
const calc = (o: Partial<PaymentOptions> = {}) =>
  calculatePayments({
    totalAmount: "100",
    currency: "EUR",
    payers: [a, b],
    paymentMode: "equal",
    ...o,
  });
describe("Swift PaymentCalculatorTests", () => {
  test.each([
    ["singlePayerEqual", "50", "EUR", [a], ["50"]],
    ["equalTwoPayers", "30", "EUR", [a, b], ["15", "15"]],
    [
      "equalThreeWayWithRemainder",
      "10",
      "USD",
      [b, c, a],
      ["3.33", "3.33", "3.34"],
    ],
    [
      "equalTwoCentRemainder",
      "0.05",
      "USD",
      [a, b, c],
      ["0.02", "0.02", "0.01"],
    ],
    ["equalZeroAmount", "0", "EUR", [a, b, c], ["0", "0", "0"]],
    ["equalJPYUsesWholeUnits", "101", "JPY", [b, a], ["50", "51"]],
  ] as const)("%s", (_name, totalAmount, currency, payers, expected) => {
    const r = calc({ totalAmount, currency, payers });
    expect(r.map((p) => fromMinor(p.amountPaid, currency))).toEqual(expected);
    expect(r.map((p) => p.payerID)).toEqual(payers);
    expect(r.every((p) => p.paymentMode === "equal")).toBe(true);
    expect(r.reduce((n, p) => n + p.amountPaid, 0n)).toBe(
      toMinor(totalAmount, currency),
    );
  });
  test.each<{
    name: string;
    o: Partial<PaymentOptions>;
    code: string;
  }>([
    {
      name: "equalInvalidCurrencyPrecisionThrows",
      o: { totalAmount: "10.25", currency: "JPY" },
      code: "amountHasTooManyFractionDigits",
    },
    {
      name: "equalEmptyPayersThrows",
      o: { totalAmount: "10", payers: [] },
      code: "emptyPayers",
    },
    {
      name: "exactSumMismatchThrows",
      o: { paymentMode: "exact", exactAmounts: { [a]: "50", [b]: "30" } },
      code: "amountsDoNotSumToTotal",
    },
    {
      name: "exactMissingPayerThrows",
      o: {
        paymentMode: "exact",
        payers: [a, b, c],
        exactAmounts: { [a]: "50", [b]: "50" },
      },
      code: "missingAmountForPayer",
    },
    {
      name: "exactExtraNonPayerThrows",
      o: {
        paymentMode: "exact",
        exactAmounts: { [a]: "40", [b]: "30", [c]: "30" },
      },
      code: "extraAmountForNonPayer",
    },
    {
      name: "exactOffByOneCentThrows",
      o: {
        totalAmount: "10",
        paymentMode: "exact",
        exactAmounts: { [a]: "5", [b]: "4.99" },
      },
      code: "amountsDoNotSumToTotal",
    },
    {
      name: "exactNilAmountsThrows",
      o: { paymentMode: "exact" },
      code: "exactAmountsRequired",
    },
  ])("$name", ({ o, code }) =>
    expect(() => calc(o)).toThrowError(expect.objectContaining({ code })),
  );
  test("exactValid", () => {
    const r = calc({
      totalAmount: "250",
      payers: [a, b, c],
      paymentMode: "exact",
      exactAmounts: { [a]: "100", [b]: "100", [c]: "50" },
    });
    expect(r.map((p) => p.amountPaid)).toEqual([10000n, 10000n, 5000n]);
    expect(r.every((p) => p.paymentMode === "exact")).toBe(true);
  });
  test("exactSinglePayer", () =>
    expect(
      calc({
        totalAmount: "99",
        payers: [a],
        paymentMode: "exact",
        exactAmounts: { [a]: "99" },
      }),
    ).toEqual([{ payerID: a, amountPaid: 9900n, paymentMode: "exact" }]));
  test.each(["percentage", "shares", "adjustment"] as const)(
    "unsupportedModes %s",
    (paymentMode) =>
      expect(() => calc({ paymentMode })).toThrowError(
        expect.objectContaining({ code: "unsupportedPaymentMode" }),
      ),
  );
  test("duplicate payers are mapped", () =>
    expect(() => calc({ payers: [a, a] })).toThrowError(
      expect.objectContaining({ code: "duplicatePayer", details: { id: a } }),
    ));
});
