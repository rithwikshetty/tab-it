import { calculateSplits, CalculationError } from "./split-calculator";
import type { Payment } from "./models";
import type { UUID, SplitType } from "./records";
export interface PaymentOptions {
  totalAmount: string;
  currency: string;
  payers: readonly UUID[];
  paymentMode: SplitType;
  exactAmounts?: Readonly<Record<UUID, string>>;
}
export function calculatePayments(options: PaymentOptions): Payment[] {
  if (!options.payers.length) throw new CalculationError("emptyPayers");
  if (options.paymentMode !== "equal" && options.paymentMode !== "exact")
    throw new CalculationError("unsupportedPaymentMode", {
      paymentMode: options.paymentMode,
    });
  if (options.paymentMode === "exact" && !options.exactAmounts)
    throw new CalculationError("exactAmountsRequired");
  try {
    return calculateSplits({
      ...options,
      participants: options.payers,
      splitType: options.paymentMode,
    }).map((s) => ({
      payerID: s.participantID,
      amountPaid: s.amountOwed,
      paymentMode: options.paymentMode,
    }));
  } catch (error) {
    if (!(error instanceof CalculationError)) throw error;
    const mapped: Record<string, string> = {
      emptyParticipants: "emptyPayers",
      duplicateParticipant: "duplicatePayer",
      missingAmountForParticipant: "missingAmountForPayer",
      extraAmountForNonParticipant: "extraAmountForNonPayer",
    };
    throw new CalculationError(mapped[error.code] ?? error.code, error.details);
  }
}
export const PaymentCalculator = { calculate: calculatePayments };
