import type { ExpensePayment } from "./records";
import { hasValidPrecision } from "./currency-catalog";
import { convertAmountText } from "./money-formatter";
import { addDecimals, normalizeDecimal } from "./decimal";
export function normalizedExactPayments<
  T extends Pick<ExpensePayment, "amount_paid" | "payment_mode">,
>(
  payments: readonly T[],
  currency: string,
): (Omit<T, "amount_paid"> & { amount_paid: string })[] {
  return payments.map((p) =>
    p.payment_mode === "exact"
      ? {
          ...p,
          amount_paid: normalizeDecimal(
            convertAmountText(p.amount_paid, currency),
          ),
        }
      : p,
  );
}
export function isPaymentLedgerValid(
  payments: readonly Pick<ExpensePayment, "amount_paid">[],
  totalAmount: string,
  currency: string,
): boolean {
  return (
    !payments.length ||
    (payments.every((p) => hasValidPrecision(p.amount_paid, currency)) &&
      addDecimals(payments.map((p) => p.amount_paid)) ===
        normalizeDecimal(totalAmount))
  );
}
export const ExpensePaymentLedger = {
  normalizedExactPayments,
  isValid: isPaymentLedgerValid,
};
