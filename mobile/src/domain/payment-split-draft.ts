import type { SplitType } from "./records";
import type { Payment, CalculatedSplit } from "./models";
import { calculateSplits, equalPercentages } from "./split-calculator";
import { calculatePayments } from "./payment-calculator";
import { addDecimals, decimalRational } from "./decimal";
import {
  decimalFromInput,
  sanitizeAmountInput,
  sanitizeShareInput,
  shareString,
} from "./money";
import { plainAmountString } from "./money-formatter";
export interface PaymentSplitDraft {
  payerMode: SplitType;
  selectedPayerIDs: string[];
  exactPayerAmountText: Record<string, string>;
  payerEdited: boolean;
  splitMode: number;
  selectedParticipants: string[];
  exactSplitAmountText: Record<string, string>;
  shareSplitText: Record<string, string>;
  percentSplitText: Record<string, string>;
  hasSeeded: boolean;
}
export function createPaymentSplitDraft(
  values: Partial<PaymentSplitDraft> = {},
): PaymentSplitDraft {
  return {
    payerMode: "equal",
    selectedPayerIDs: [],
    exactPayerAmountText: {},
    payerEdited: false,
    splitMode: 0,
    selectedParticipants: [],
    exactSplitAmountText: {},
    shareSplitText: {},
    percentSplitText: {},
    hasSeeded: false,
    ...values,
  };
}
const copy = (s: PaymentSplitDraft): PaymentSplitDraft => ({
  ...s,
  selectedPayerIDs: [...s.selectedPayerIDs],
  selectedParticipants: [...s.selectedParticipants],
  exactPayerAmountText: { ...s.exactPayerAmountText },
  exactSplitAmountText: { ...s.exactSplitAmountText },
  shareSplitText: { ...s.shareSplitText },
  percentSplitText: { ...s.percentSplitText },
});
export function selectedSplitType(draft: PaymentSplitDraft): SplitType {
  return draft.splitMode === 0
    ? "equal"
    : draft.splitMode === 2
      ? "shares"
      : draft.splitMode === 3
        ? "percentage"
        : "exact";
}
export function enteredDraftTotal(
  ids: readonly string[],
  text: Readonly<Record<string, string>>,
): string {
  return addDecimals(ids.map((id) => decimalFromInput(text[id] ?? "") ?? "0"));
}
function seedPayers(
  draft: PaymentSplitDraft,
  totalAmount: string,
  currency: string,
  overwrite: boolean,
) {
  if (
    !draft.selectedPayerIDs.length ||
    decimalRational(totalAmount).numerator <= 0n
  )
    return;
  let computed: Payment[];
  try {
    computed = calculatePayments({
      totalAmount,
      currency,
      payers: draft.selectedPayerIDs,
      paymentMode: "equal",
    });
  } catch {
    return;
  }
  draft.exactPayerAmountText = Object.fromEntries(
    Object.entries(draft.exactPayerAmountText).filter(([id]) =>
      draft.selectedPayerIDs.includes(id),
    ),
  );
  for (const p of computed)
    if (overwrite || !draft.exactPayerAmountText[p.payerID]?.trim())
      draft.exactPayerAmountText[p.payerID] = plainAmountString(
        p.amountPaid,
        currency,
      );
}
function seedSplits(
  draft: PaymentSplitDraft,
  totalAmount: string,
  currency: string,
  overwrite = false,
) {
  const type = selectedSplitType(draft);
  if (type === "shares") {
    for (const id of draft.selectedParticipants)
      if (!draft.shareSplitText[id]?.trim()) draft.shareSplitText[id] = "1";
  } else if (type === "percentage") {
    const equal = equalPercentages(draft.selectedParticipants);
    for (const id of draft.selectedParticipants)
      if (!draft.percentSplitText[id]?.trim())
        draft.percentSplitText[id] = shareString(equal[id]!);
  } else if (
    type === "exact" &&
    draft.selectedParticipants.length &&
    decimalRational(totalAmount).numerator > 0n
  ) {
    let splits: CalculatedSplit[];
    try {
      splits = calculateSplits({
        totalAmount,
        currency,
        participants: draft.selectedParticipants,
        splitType: "equal",
      });
    } catch {
      return;
    }
    for (const s of splits)
      if (overwrite || !draft.exactSplitAmountText[s.participantID]?.trim())
        draft.exactSplitAmountText[s.participantID] = plainAmountString(
          s.amountOwed,
          currency,
        );
  }
}
export function seedPaymentSplitDraft(
  draft: PaymentSplitDraft,
  options: {
    payments: readonly Payment[];
    splitMode: number;
    participantSet: readonly string[];
    exactSplitAmountText: Record<string, string>;
    shareSplitText: Record<string, string>;
    percentSplitText: Record<string, string>;
    currency: string;
    currentPersonID: string | null;
    members: readonly string[];
  },
): PaymentSplitDraft {
  if (draft.hasSeeded) return draft;
  const d = copy(draft);
  d.hasSeeded = true;
  d.selectedPayerIDs = options.payments.length
    ? [...new Set(options.payments.map((p) => p.payerID))]
    : [options.currentPersonID ?? options.members[0]].filter(
        (id): id is string => id !== undefined && id !== null,
      );
  d.payerMode = options.payments[0]?.paymentMode ?? "equal";
  if (d.payerMode === "exact") {
    d.payerEdited = true;
    d.exactPayerAmountText = Object.fromEntries(
      options.payments.map((p) => [
        p.payerID,
        plainAmountString(p.amountPaid, options.currency),
      ]),
    );
  }
  d.splitMode = options.splitMode;
  d.selectedParticipants = [...new Set(options.participantSet)];
  d.exactSplitAmountText = Object.fromEntries(
    Object.entries(options.exactSplitAmountText).map(([id, s]) => [
      id,
      sanitizeAmountInput(s, options.currency),
    ]),
  );
  d.shareSplitText = Object.fromEntries(
    Object.entries(options.shareSplitText).map(([id, s]) => [
      id,
      sanitizeShareInput(s),
    ]),
  );
  d.percentSplitText = Object.fromEntries(
    Object.entries(options.percentSplitText).map(([id, s]) => [
      id,
      sanitizeShareInput(s),
    ]),
  );
  if (d.splitMode === 2 || d.splitMode === 3)
    seedSplits(d, "0", options.currency);
  return d;
}
export function setPayerMode(
  draft: PaymentSplitDraft,
  mode: SplitType,
  totalAmount: string,
  currency: string,
): PaymentSplitDraft {
  const d = copy(draft);
  d.payerMode = mode;
  if (mode === "exact") {
    d.payerEdited = false;
    seedPayers(d, totalAmount, currency, true);
  }
  return d;
}
export function togglePayer(
  draft: PaymentSplitDraft,
  id: string,
  totalAmount: string,
  currency: string,
): PaymentSplitDraft {
  const d = copy(draft),
    selected = d.selectedPayerIDs.includes(id);
  if (selected) {
    if (d.selectedPayerIDs.length <= 1) return draft;
    d.selectedPayerIDs = d.selectedPayerIDs.filter((p) => p !== id);
    delete d.exactPayerAmountText[id];
  } else d.selectedPayerIDs.push(id);
  if (d.payerMode === "exact")
    seedPayers(
      d,
      totalAmount,
      currency,
      !d.payerEdited || (selected && d.selectedPayerIDs.length === 1),
    );
  return d;
}
export function setDraftText(
  draft: PaymentSplitDraft,
  field: "payer" | "exact" | "shares" | "percentage",
  id: string,
  input: string,
  currency = "USD",
): PaymentSplitDraft {
  const d = copy(draft);
  if (field === "payer") {
    d.payerEdited = true;
    d.exactPayerAmountText[id] = sanitizeAmountInput(input, currency);
  } else if (field === "exact")
    d.exactSplitAmountText[id] = sanitizeAmountInput(input, currency);
  else if (field === "shares") d.shareSplitText[id] = sanitizeShareInput(input);
  else d.percentSplitText[id] = sanitizeShareInput(input);
  return d;
}
export function setSplitMode(
  draft: PaymentSplitDraft,
  mode: number,
  totalAmount: string,
  currency: string,
  overwriteExactAmounts = false,
): PaymentSplitDraft {
  const d = copy(draft);
  d.splitMode = mode;
  seedSplits(d, totalAmount, currency, overwriteExactAmounts);
  return d;
}
export function toggleParticipant(
  draft: PaymentSplitDraft,
  id: string,
  totalAmount: string,
  currency: string,
): PaymentSplitDraft {
  const d = copy(draft);
  if (d.selectedParticipants.includes(id)) {
    if (d.selectedParticipants.length <= 1) return draft;
    d.selectedParticipants = d.selectedParticipants.filter((p) => p !== id);
  } else d.selectedParticipants.push(id);
  seedSplits(d, totalAmount, currency);
  return d;
}
function entered(
  ids: readonly string[],
  text: Readonly<Record<string, string>>,
): Record<string, string> | null {
  const values: Record<string, string> = {};
  for (const id of ids) {
    const value = decimalFromInput(text[id]?.trim() ?? "");
    if (value === null) return null;
    values[id] = value;
  }
  return values;
}
export function computedDraftPayments(
  d: PaymentSplitDraft,
  totalAmount: string,
  currency: string,
): Payment[] | null {
  if (
    !d.selectedPayerIDs.length ||
    decimalRational(totalAmount).numerator <= 0n
  )
    return null;
  const amounts =
    d.payerMode === "exact"
      ? entered(d.selectedPayerIDs, d.exactPayerAmountText)
      : undefined;
  if (amounts === null) return null;
  try {
    return calculatePayments({
      totalAmount,
      currency,
      payers: d.selectedPayerIDs,
      paymentMode: d.payerMode,
      exactAmounts: amounts,
    });
  } catch {
    return null;
  }
}
export function computedDraftSplits(
  d: PaymentSplitDraft,
  totalAmount: string,
  currency: string,
): CalculatedSplit[] | null {
  if (
    !d.selectedParticipants.length ||
    decimalRational(totalAmount).numerator <= 0n
  )
    return null;
  const type = selectedSplitType(d),
    amounts =
      type === "equal"
        ? undefined
        : entered(
            d.selectedParticipants,
            type === "exact"
              ? d.exactSplitAmountText
              : type === "shares"
                ? d.shareSplitText
                : d.percentSplitText,
          );
  if (amounts === null) return null;
  try {
    return calculateSplits({
      totalAmount,
      currency,
      participants: d.selectedParticipants,
      splitType: type,
      exactAmounts: amounts,
      shares: amounts,
      percentages: amounts,
    });
  } catch {
    return null;
  }
}
