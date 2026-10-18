import { sanitizeAmountInput } from "./money";
import { convertAmountText } from "./money-formatter";
export interface SettlementAmountDraft {
  text: string;
  wasUserEdited: boolean;
  shouldPrefill: boolean;
}
export function createSettlementAmountDraft(): SettlementAmountDraft {
  return { text: "", wasUserEdited: false, shouldPrefill: true };
}
export function userChangedSettlementText(draft: SettlementAmountDraft, input: string, currency: string): SettlementAmountDraft {
  return {
    text: sanitizeAmountInput(input, currency),
    wasUserEdited: true,
    shouldPrefill: false,
  };
}
export function setProgrammaticSettlementText(draft: SettlementAmountDraft, text: string): SettlementAmountDraft {
  return { ...draft, text };
}
export function convertSettlementDraft(draft: SettlementAmountDraft, currency: string): SettlementAmountDraft {
  return { ...draft, text: convertAmountText(draft.text, currency) };
}
