# Normalize balances to cross-settled debts everywhere

## Goal (2026-07-15)

User report: opening an individual balance from the trip Balances tab prefills the
settle-up form with the wrong amount (not the cross-settled one). Also: the
"SIMPLIFIED DEBTS" framing should go — cross-settlement is the standard way the
app balances debts, not a special mode.

## Findings (2026-07-15)

- Trip Balances rows and BalanceCard details already present simplified
  (cross-settled) debts. Good.
- `SettleUpFormView` is pairwise-based: `pairBalance` drives the context banner,
  and `updateAmountForPair()` looks up raw pairwise balances.
- Root bug: `currency` state starts at `CurrencyDefaults.initialCurrency`;
  `prepopulate()` (onAppear) sets it to the tapped row's currency. When they
  differ, `.onChange(of: currency)` fires and `updateAmountForPair()` overwrites
  the simplified suggestion amount with the raw pairwise balance.
- Banner can contradict the tapped row (simplified 30 vs pairwise 10 → "overpays
  by 20") because it reads pairwise numbers.
- `SettleUpPresenter.suggestedPayment` (no-suggestion fallback) picks from raw
  pairwise balances.
- Friends tab list, friend hero, and "Balance by source" rows aggregate raw
  pairwise balances (`FriendsPresenter.Context` feeds `BalanceEngine` output
  straight into `OverallBalanceAggregator`), so they can disagree with the trip
  screens. `TripPresenter.card` already mirrors simplified debts into
  `UserBalance` rows for state derivation — same pattern to reuse.
- Tapping a friend source row routes `.settleUp(tripID:, suggestion: nil)` —
  form falls back to the user's largest debt with anyone, not that friend.

## Decision (2026-07-15)

Cross-settled (simplified) debts are the canonical presentation everywhere;
pair-level expense/settlement history stays the stored source of truth.
Surfaces to change: settle-up form (prefill, banner, selectable people,
fallback suggestion), FriendsPresenter aggregation, friend source-row settle
suggestion, trip Balances section header (drop "SIMPLIFIED DEBTS" framing;
keep a plain currency label only for multi-currency trips).

Implementation routed to Codex (workspace-write) per global working agreement.

## Implementation (2026-07-15 08:03 BST)

- Replaced settle-up form pairwise lookups with trip-wide debt simplification for
  amount updates, context messaging, and removed-member selection.
- Reworked default settle-up suggestions to choose deterministically from
  trip-wide debts, preferring a debt paid by the current person.
- Normalized Friends presenter containers through the same mirrored-debt pattern
  used by trip cards, and attached exact settle-up suggestions to source rows.
- Routed friend source taps with their suggestion and removed the special debt
  framing from the trip balance cards.
- Updated existing prefill expectations and added regressions for an A-to-C
  redirected payment and a three-person Friends balance/source suggestion.
- Initial diff inspection and `git diff --check` passed; focused builds and tests
  remain to run.

## Validation (2026-07-15 08:06 BST)

- Confirmed the shared Xcode project and scheme are `Apps/Tab/Tab.xcodeproj`
  and `Tab`.
- The exact requested Xcode test command could not reach compilation: the
  managed environment denies writes to the user Swift/Clang caches and cannot
  connect to CoreSimulatorService.
- Retrying with caches and DerivedData under `/tmp` advanced to package manifest
  resolution, where Xcode's nested `sandbox-exec` was rejected by the outer
  managed sandbox.
- The exact `swift test` command hit the same cache denial. Retrying the same
  TabCore suite with writable module caches and `--disable-sandbox` passed all
  152 tests in 11 suites.
- Swift parser validation passed for all eight changed app/test files;
  `git diff --check` passed; there are no diffs under `Packages/TabCore` or
  `supabase/`; and no user-facing Swift string contains the forbidden term.

## Review + independent validation (2026-07-15 08:12 BST)

- Reviewed the full Codex diff by hand: direction logic in
  `FriendSourceRow.suggestion`, the mirrored-debt aggregation in
  `FriendsPresenter.Context`, and the direction-aware prefill in
  `updateAmountForPair()` all check out. Verified the reworked exporter test
  scenario arithmetically (Alice nets +135; her 15 EUR debt to Bob is
  cross-settled away, so the fallback suggestion is Cara pays Alice 135).
- Re-ran the unit suite locally outside Codex's sandbox:
  `xcodebuild -project Apps/Tab/Tab.xcodeproj -scheme Tab -only-testing:TabTests
  test` on iPhone 17 — 90 tests in 18 suites, TEST SUCCEEDED.
- Note: `updateAmountForPair()` now only prefills when the From person actually
  owes the To person in the cross-settled model; picking a reversed pair leaves
  the typed amount alone and the banner flags the direction instead.
