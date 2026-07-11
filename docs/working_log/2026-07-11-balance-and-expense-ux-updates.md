# Balance and expense UX updates

## Goal

Create GitHub issues for the five requested expense and balance improvements, update the documented scope to include simplified trip debts, implement every issue on `main`, and verify the resulting app and pure logic.

## 2026-07-11 11:19 ICT — Requests clarified

Confirmed the intended issue split: show the current viewer's share in expense rows plus daily totals; simplify trip debts; remove the Overview daily-spend card; let joined trip members inspect all shares and debts within that trip, including pending/non-app trip people; and consistently colour lent versus borrowed values. Visibility must remain trip-scoped. Simplified debts intentionally replaces the earlier out-of-scope decision.

## 2026-07-11 11:22 ICT — Implementation authorised

The user asked for all five issues to be implemented directly on the current `main` branch after issue creation, with useful issue comments. The execution plan uses the issues as the implementation checklist and closes each only after relevant verification passes.

## 2026-07-11 11:29 ICT — Issues created and scope documented

Created GitHub issues #8 through #12, one per requested change, with acceptance criteria covering multi-currency grouping, deterministic debt simplification, pending trip people, strict trip visibility, and accessible colour semantics. Selected the locked deep sage (`#4F7549`) for lent/owed and warm rust (`#B16D3F`) for borrowed/owing. Updated `AGENTS.md`, `CLAUDE.md`, and `CONTEXT.md`: simplified debts are now an in-scope, derived per-trip/per-currency presentation that never replaces raw pair balances or ledger history; joined members may inspect all ledger shares and debts only inside their trip; Overview no longer includes daily spend.

## 2026-07-11 11:34 ICT — Feature implementation complete

Implemented `DebtSimplifier` in TabCore. It consumes mirrored raw `UserBalance` rows, derives member net positions independently per currency, and deterministically matches the largest debtors and creditors with UUID tie-breaks. Trip completion now follows the simplified debt set, so a fully cancelling raw cycle does not keep a trip active. The Balances tab shows the same group-wide simplified rows to every member and each row opens Settle up with people, currency, and amount prefilled.

Updated the expense timeline to show the signed-in trip person's split share as the trailing row value. Each row separately labels a positive net contribution as “you lent” and a negative one as “you borrowed.” Date headers now aggregate full spend plus the viewer share, separately per currency and excluding settlements. Applied deep sage to lent/owed states and warm rust to borrowed/owing states across the modified rows and balance cards; mixed trip-card currency directions remain neutral.

Expense detail now lists every payer and paid amount instead of collapsing multi-payer expenses to “N people”; the existing split card already lists every participant share. Together with the new all-member simplified Balances tab, this exposes other-member and pending-person ledger information inside the current trip without changing the existing trip-scoped RLS boundary. Removed the Overview daily-spend card, view-state, presenter mapping, core daily aggregation type, and obsolete tests while retaining totals, people, and categories.

## 2026-07-11 11:36 ICT — Verification

TabCore passed 152 Swift Testing tests, including seven new debt-simplification scenarios. The app unit target passed 86 tests, including new timeline aggregation/semantic-direction coverage and a trip-wide pending-person debt presentation test. The generic iOS Simulator app build succeeded. The existing mock-auth seeded trip UI test passed after repeatedly switching Expenses, Balances, and Overview and scrolling the expense timeline. SQL assembly remained up to date; existing RLS tests already cover member read access and non-member denial for expense payments and splits. A simulator screenshot confirmed the sage/rust semantics remain visually coherent on trip rows. The first fresh simulator test launch logged SwiftData creating its missing Application Support store and then recovered successfully; tests were unaffected.

## 2026-07-11 11:40 ICT — Published and issues closed

Committed the implementation as `5a1e114` on `main` and pushed it to `origin/main`. The push also published the pre-existing local-main commit `8b0f869`; no history was rewritten. Added an issue-specific implementation and verification comment to GitHub issues #8, #9, #10, #11, and #12, then closed all five as completed.
