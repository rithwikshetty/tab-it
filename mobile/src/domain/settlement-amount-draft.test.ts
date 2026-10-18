import { expect, test } from "vitest";
import {
  createSettlementAmountDraft as create,
  userChangedSettlementText as user,
  setProgrammaticSettlementText as program,
  convertSettlementDraft as convert,
} from "./settlement-amount-draft";
test("untouchedAmountCanBePrefilled", () => {
  const d = create();
  expect(d.shouldPrefill).toBe(true);
});
test("typedAmountCannotBePrefilled", () => {
  const d = user(create(), "25.50", "EUR");
  expect(d.text).toBe("25.50");
  expect(d.shouldPrefill).toBe(false);
});
test("typedAmountStaysEditedAfterCurrencyChange", () => {
  const d = convert(user(create(), "25.50", "EUR"), "JPY");
  expect(d.text).toBe("26");
  expect(d.shouldPrefill).toBe(false);
});
test("clearedAmountCannotBePrefilled", () => {
  const d = user(program(create(), "40.00"), "", "EUR");
  expect(d.text).toBe("");
  expect(d.shouldPrefill).toBe(false);
});
