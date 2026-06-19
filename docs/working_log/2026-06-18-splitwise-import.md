# Splitwise CSV import

Goal: let users import an existing Splitwise group export (CSV) into tab as a new
trip, with expenses and settlements reconstructed so balances match Splitwise
exactly. Self column maps to the current account; everyone else becomes a
name-only trip person (synthetic email). Fully native, no new dependencies.

## 2026-06-18 — kickoff & design

- Inspected the real export `~/Downloads/Splitwise expenses Jun 18.csv`.
  - Header: `Date,Description,Category,Cost,Currency,<Person…>`; one signed **net**
    column per person (`paid - owed`). Trailing blank line + a `Total balance` row.
  - Three row kinds: real expenses; explicit payments (`Category == Payment`,
    e.g. "Lym paid Sparsh K."); and `Settle all balances` rows (tagged `General`
    but are settlements — two equal/opposite entries).
- Confirmed keystone math in TabCore:
  - `BalanceEngine` computes balances purely from per-person nets, so any
    reconstruction preserving each person's net is balance-exact. A 2-person
    settlement and its expense-reconstruction yield identical balances — so
    classification can never corrupt math, only presentation.
  - Settlement sign (`BalanceEngine.swift:37`): from = payer (positive net column),
    to = recipient (negative net column). Matches "X paid Y" descriptions.
  - `SplitCalculator.calculateExact` requires splits to sum exactly to total with
    valid currency precision → reconstruction works in minor units and distributes
    the cent remainder deterministically (largest fractional remainder, lowest
    name on ties), mirroring existing conventions.
- Confirmed app write paths: trip + creator person (`NewTripSheet`/`create_trip_with_self`),
  other people via `SyncService.addTripPerson` → `add_trip_person_by_email` RPC
  (requires an email → synthetic `<uuid>@users.tab`, an existing convention at
  `SyncService.swift:719`). Locally-inserted non-creator people never sync, so the
  importer must add others through the RPC. Implies import needs connectivity
  (same as adding anyone to a trip).
- Project uses XcodeGen (`Apps/Tab/project.yml`) globbing `Sources/Tab`; new files
  register via `xcodegen generate`. Entry point goes in `NewTripSheet` (the `+`
  button is asserted directly by UI tests, so it must stay a direct action).

Plan: (1) pure `SplitwiseImport` parser + tests in TabCore; (2) `SplitwiseImporter`
app service; (3) `ImportFromSplitwiseSheet` UI + entry point in `NewTripSheet`;
(4) regenerate, build, simulator smoke test; (5) adversarial review workflow.

## 2026-06-18 — parser done, validated end-to-end

- `SplitwiseImport` parser written. 14 TabCore tests pass, incl. the gold check:
  parse the real export → build `Expense`/`Settlement` → `BalanceEngine.compute`
  → every person's net equals Splitwise's `Total balance` row exactly
  (Rithwik 5.76, Lym -11.52, Shreya -5.76, Sachin 11.52, Sparsh 0, Esha 0).
  Multi-payer (Peacock: 3×28.80 paid, 5×17.28 owed) and unequal cents (Paste tax
  Lym 0.24 not 0.25) both reconstruct exactly. 9 expenses, 22 settlements parsed.
- Confirmed the people-sync path: `add_trip_person_by_email` accepts a client
  `p_person_id`, and `SyncMerge.apply(TripPersonDTO)` inserts the person linked to
  the trip with that id. So `addTripPerson` will take an optional `personID` —
  the importer controls ids and keeps local state consistent (no re-fetch).
  Mock auth has no session (`hasRealSession == false`), so under mock the importer
  inserts other people locally (mirrors `NewTripSheet`'s debug-people path); under
  a real session it goes through the RPC so they sync.

## 2026-06-18 — app layer + simulator verification

- Built `SplitwiseImporter` (service) + `ImportFromSplitwiseSheet` (UI) + entry
  point in `NewTripSheet` ("Import from Splitwise" row). `addTripPerson` gained an
  optional `personID` (and `@discardableResult` return) — backward compatible.
- Added pure-glue tests (`TabTests/SplitwiseImporterTests`): category mapping and
  self-column matching. (Skipped a full importer integration test — building a
  signed-in `AuthService` in a unit test is flaky and out of proportion; the
  parser's end-to-end balance test already covers the math.)
- `xcodegen generate` registers the new files (folder glob). App builds clean for
  the simulator; TabCore suite is 122 green.
- Simulator (mock auth): app launches → Trips list. Couldn't drive the flow (no
  `tap` tool here; the system file picker can't reach a Mac-side CSV from the sim
  anyway), so used a temporary, clearly-marked debug harness to render the review
  screen from a fixture, screenshotted it (styling/picker/"You" chip/summary all
  correct: 3-row fixture → 2 expenses + 1 settlement), then removed the harness
  and reconfirmed a clean build.
- Next: adversarial multi-dimension review workflow over the new code.

## 2026-06-18 — adversarial review + fixes

Ran a 4-dimension review workflow (parser math / importer-sync-concurrency / SwiftUI
/ conventions), each finding independently verified. 16 confirmed. Fixing:

- CRITICAL: `auth.isUsingMockAuth` is `#if DEBUG`-only — my unguarded use in
  `SplitwiseImporter.makePerson` broke the Release archive (Debug builds hid it).
  Gated behind `#if DEBUG` (production default = the `addTripPerson` RPC path).
- HIGH: duplicate header names. Parser kept both columns (warning lied: "treated
  as one person") → importer collapsed them to one id → duplicate
  `(expense_id, trip_person_id)` rows → PK violation on push / lost money. Fixed:
  parser now genuinely merges same-name columns (sums their nets), `people` is
  deduped (also fixes duplicate SwiftUI ForEach ids), warning made truthful.
- MED: `Double` used for payer-share allocation (CLAUDE.md: Decimal only). Rewrote
  in integer minor-unit math (largest-remainder, name tiebreak) like BalanceEngine.
- MED: `Decimal(string:)` silently truncates "1,234.56" → "1". Added strict
  plain-decimal validation; non-empty unparseable cells skip the row with a warning
  instead of silently zeroing a net.
- MED: drift absorption could push a payer negative and get it filtered out, so
  payments no longer summed to total. Added post-reconstruction validation that
  skips the row if sums/signs don't hold.
- MED: partial import failure left an orphaned/half-synced trip and a retry made a
  duplicate. `run()` now soft-deletes the trip on failure (syncs the tombstone) so
  retries start clean.
- MED: self defaulted to the first column on no name match (silent misattribution).
  Now defaults to "not in this group" when there's no match.
- LOW: parser strips a leading UTF-8 BOM itself (was only in the UI); `phase` enum
  collapsed to `isImporting`; `.interactiveDismissDisabled` while importing;
  dropped the unused `Outcome` return.

## 2026-06-18 — fix-verification round

Ran a second (lean) verification workflow over the changed files. Found 3, all fixed:

- HIGH (regression I introduced): switching the payer-share split to `Int` made
  `payersOwedTotal * payer.net` overflow Int64 for very large expenses (~£100M, or
  4-decimal currencies near 1M) → a hard trap, not a skipped row. Rewrote the
  proportion in `Decimal` (38-digit), floored to Int — matches BalanceEngine.
  Added a regression test (£100M two-party expense) that would crash the old code.
- LOW: initial trip+creator `save()` sat outside the do/catch, so a save failure
  could strand a live trip. Moved insert+save inside the do block.
- LOW: the failure catch-path's `pushPending()` futilely pushed settlements under
  the just-soft-deleted trip (server rejects → spurious sync error). Added a
  deleted-trip guard in `pushSettlements`, mirroring the existing expense path.

Final state: TabCore 127 tests green (incl. overflow + dedup + separator + BOM +
unbalanced-skip), app 67 tests green, Release AND Debug builds clean. Feature
complete: pure parser + importer + UI + entry point, DB/export untouched.
