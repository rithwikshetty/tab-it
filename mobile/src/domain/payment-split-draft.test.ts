import { expect, test } from "vitest";
import {
  createPaymentSplitDraft as create,
  setPayerMode,
  togglePayer,
  setDraftText,
  setSplitMode,
  toggleParticipant,
  computedDraftPayments as payments,
  computedDraftSplits as splits,
  seedPaymentSplitDraft,
  enteredDraftTotal,
} from "./payment-split-draft";
import {
  normalizedExactPayments,
  isPaymentLedgerValid,
} from "./expense-payment-ledger";
import { a, b } from "./test-support";
test("exactModeUntoggleToOnePayerStaysValid", () => {
  let d = setPayerMode(
    create({ selectedPayerIDs: [a, b] }),
    "exact",
    "100",
    "USD",
  );
  d = setDraftText(d, "payer", b, "30", "USD");
  d = togglePayer(d, b, "100", "USD");
  expect(d.selectedPayerIDs).toEqual([a]);
  expect(payments(d, "100", "USD")).toEqual([
    { payerID: a, amountPaid: 10000n, paymentMode: "exact" },
  ]);
});
test("singleExactPayerCoversTotal", () =>
  expect(
    payments(
      togglePayer(
        setPayerMode(
          create({ selectedPayerIDs: [a, b] }),
          "exact",
          "80",
          "USD",
        ),
        b,
        "80",
        "USD",
      ),
      "80",
      "USD",
    )?.[0]?.amountPaid,
  ).toBe(8000n));
test("sharesModeSeedsOnes", () => {
  const d = setSplitMode(
    create({ selectedParticipants: [a, b] }),
    2,
    "30",
    "USD",
  );
  expect(d.shareSplitText).toEqual({ [a]: "1", [b]: "1" });
  expect(splits(d, "30", "USD")?.map((s) => s.amountOwed)).toEqual([
    1500n,
    1500n,
  ]);
});
test("sharesModeWeightedSplit", () => {
  let d = setSplitMode(
    create({ selectedParticipants: [a, b] }),
    2,
    "30",
    "USD",
  );
  d = setDraftText(d, "shares", a, "2");
  d = setDraftText(d, "shares", b, "0.5");
  expect(
    splits(d, "30", "USD")?.map((s) => [s.amountOwed, s.shareUnits]),
  ).toEqual([
    [2400n, "2"],
    [600n, "0.5"],
  ]);
});
test("sharesModeEmptyShareBlocks", () => {
  const d = setDraftText(
    setSplitMode(create({ selectedParticipants: [a, b] }), 2, "30", "USD"),
    "shares",
    b,
    "",
  );
  expect(splits(d, "30", "USD")).toBeNull();
});
test("sharesModeToggleSeedsNewParticipant", () => {
  const d = toggleParticipant(
    setSplitMode(create({ selectedParticipants: [a] }), 2, "30", "USD"),
    b,
    "30",
    "USD",
  );
  expect(d.shareSplitText[b]).toBe("1");
  expect(splits(d, "30", "USD")).toHaveLength(2);
});
test("percentModeSeedsEqual", () => {
  const d = setSplitMode(
    create({ selectedParticipants: [a, b] }),
    3,
    "80",
    "USD",
  );
  expect(d.percentSplitText).toEqual({ [a]: "50", [b]: "50" });
  expect(splits(d, "80", "USD")?.map((s) => s.amountOwed)).toEqual([
    4000n,
    4000n,
  ]);
});
test("percentModeWeightedSplit", () => {
  let d = setSplitMode(
    create({ selectedParticipants: [a, b] }),
    3,
    "80",
    "USD",
  );
  d = setDraftText(d, "percentage", a, "75");
  d = setDraftText(d, "percentage", b, "25");
  expect(
    splits(d, "80", "USD")?.map((s) => [s.amountOwed, s.percentage]),
  ).toEqual([
    [6000n, "75"],
    [2000n, "25"],
  ]);
});
test("percentModeMustSumTo100", () => {
  let d = setSplitMode(
    create({ selectedParticipants: [a, b] }),
    3,
    "80",
    "USD",
  );
  d = setDraftText(d, "percentage", a, "75");
  d = setDraftText(d, "percentage", b, "24");
  expect(splits(d, "80", "USD")).toBeNull();
});
test("exactPaymentsFollowCurrencyPrecision", () => {
  const r = normalizedExactPayments(
    [
      { amount_paid: "600.25", payment_mode: "exact" },
      { amount_paid: "400.25", payment_mode: "exact" },
    ] as const,
    "JPY",
  );
  expect(r.map((p) => p.amount_paid)).toEqual(["600", "400"]);
  expect(r.every((p) => p.payment_mode === "exact")).toBe(true);
});
test("individualPaymentPrecisionIsValidated", () => {
  expect(
    isPaymentLedgerValid(
      [{ amount_paid: "600.5" }, { amount_paid: "399.5" }],
      "1000",
      "JPY",
    ),
  ).toBe(false);
  expect(
    isPaymentLedgerValid(
      [{ amount_paid: "600" }, { amount_paid: "400" }],
      "1000",
      "JPY",
    ),
  ).toBe(true);
  expect(isPaymentLedgerValid([], "1000", "JPY")).toBe(true);
});
test("draft seeding only runs once and preserves exact ledger", () => {
  const options = {
    payments: [
      { payerID: a, amountPaid: 1234n, paymentMode: "exact" as const },
    ],
    splitMode: 2,
    participantSet: [a, b],
    exactSplitAmountText: {},
    shareSplitText: { [a]: "0,5" },
    percentSplitText: {},
    currency: "USD",
    currentPersonID: a,
    members: [a, b],
  };
  const d = seedPaymentSplitDraft(create(), options);
  expect(d.exactPayerAmountText[a]).toBe("12.34");
  expect(d.shareSplitText).toEqual({ [a]: "0.5", [b]: "1" });
  expect(seedPaymentSplitDraft(d, { ...options, currency: "JPY" })).toBe(d);
  expect(enteredDraftTotal([a, b], { [a]: "12.34", [b]: "0.66" })).toBe("13");
});
