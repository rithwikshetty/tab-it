# Symbol-only money format + clearer day-total label

## 2026-07-15 — Goal

Two UI wording complaints from Rithwik:

1. Amounts render as ISO code + symbol + number ("THB ฿1,200.00"). The code is
   noise — show just the symbol and number.
2. The per-day totals in the trip Expenses tab read "€38.00 (you €9.50)".
   "(you …)" is cryptic — say "your share".

## 2026-07-15 — Findings

- All code-prefixed rendering funnels through `MoneyFormatter.format`. A
  second function, `formatSymbol`, already did exactly the symbol-only
  rendering we want (with a `CODE value` fallback for currencies whose symbol
  IS the code, e.g. CHF).
- The "(you …)" string exists in exactly one place:
  `TripDetailView.timelineSection`. `ExpenseRow` already labels its trailing
  amount "your share", so the day header now matches it.
- `TripExporter` uses `MoneyFormatter.format` for the Paid By / Split detail
  cells. Exports switch to symbol-only too; fine — the expense sheet has a
  dedicated Currency column, and the exporter tests build their fixture
  strings by hand so nothing broke.
- `CurrencyPill` (expense entry / settle-up forms) intentionally shows
  "₹ INR ▾" — it is the currency *picker*, so the code stays.

## 2026-07-15 — Changes

- `MoneyFormatter.format` now renders symbol-only (the old `formatSymbol`
  body); `formatSymbol` deleted and all call sites switched to `format`
  (ActivityPresenter, OverviewPresenter, FriendsPresenter, FriendsView,
  OverviewPresenterTests).
- `TripDetailView` day header: `"total (you share)"` → `"total · your share X"`.

## 2026-07-15 — Validation

- Full `test_sim` run: 102/102 passed (unit + UI tests).
- Exported the marketing-screenshot UI test attachments and visually checked
  trip detail + friends screens: symbol-only amounts everywhere, day header
  reads "€38.00 · your share €9.50", long-THB stress layout unaffected
  (lineLimit 1 + minimumScaleFactor already in place).

## 2026-07-15 — Codex review flagged shared-symbol ambiguity (P2)

With the ISO code gone, currencies sharing a symbol became indistinguishable
on mixed-currency surfaces (Friends, Activity): USD/CAD/AUD/MXN all rendered
as bare "$", and CNY's fullwidth "￥" was a visual twin of JPY's "¥".

Fix in `CurrencyCatalog.makeLocalizedSymbolsByCode` — display symbols are now
globally unique across the supported set:

- Added `en_US` as a candidate source: home locales only ever offer the bare
  symbol; ICU's disambiguated forms ("A$", "MX$", "CN¥") live in foreign
  locales. Also guarantees every supported code enters the claim pass.
- Claim pass in most-traded order (`symbolClaimPriority`): USD keeps "$",
  GBP "£", JPY "¥"; later claimants take their shortest still-free candidate
  (CAD → "CA$", AUD → "A$", NZD → "NZ$", MXN → "MX$", CNY → "CN¥") or fall
  back to their code (SGD, NOK, ARS…), which `format` renders as "CODE value".
- Claim keys are NFKC-folded so lookalikes count as collisions (fullwidth ￥).

New TabCore tests: global symbol uniqueness (NFKC-folded) + majors keep bare
symbols / dollar currencies disambiguate.

## 2026-07-15 — Final validation

- TabCore: 154/154 passed.
- App `test_sim`: 102/102 passed (unit + UI).
