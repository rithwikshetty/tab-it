import { expect, test } from "vitest";
import { ledgerFromRows, paymentMethodDisplayName } from "./models";
import { addExpense, tripRows, rowSettlement, a, b } from "./test-support";
test("pulledMoneyIsNormalized at the pure row-to-ledger boundary", () => {
  let rows = addExpense(
    tripRows(),
    "e",
    { [a]: "10.005" },
    { [b]: "10.004" },
    "10.005",
  );
  rows = rowSettlement(rows, a, b, "0.4", "JPY");
  const inserted = ledgerFromRows(rows);
  expect(inserted.expenses[0]?.amount.amount).toBe(1001n);
  expect(inserted.expenses[0]?.payments[0]?.amountPaid).toBe(1001n);
  expect(inserted.expenses[0]?.splits[0]?.amountOwed).toBe(1000n);
  expect(inserted.settlements[0]?.amount.amount).toBe(0n);
  const updated = ledgerFromRows({
    ...rows,
    expenses: rows.expenses.map((e) => ({ ...e, amount: "20.004" })),
    payments: rows.payments.map((p) => ({ ...p, amount_paid: "20.004" })),
    splits: rows.splits.map((s) => ({ ...s, amount_owed: "20.005" })),
    settlements: rows.settlements.map((s) => ({ ...s, amount: "1.5" })),
  });
  expect(updated.expenses[0]?.amount.amount).toBe(2000n);
  expect(updated.expenses[0]?.payments[0]?.amountPaid).toBe(2000n);
  expect(updated.expenses[0]?.splits[0]?.amountOwed).toBe(2001n);
  expect(updated.settlements[0]?.amount.amount).toBe(2n);
});
test("payment methods expose the native display names", () => {
  expect(paymentMethodDisplayName("cash")).toBe("Cash");
  expect(paymentMethodDisplayName("card")).toBe("Card");
  expect(paymentMethodDisplayName("bank_transfer")).toBe("Bank transfer");
});
