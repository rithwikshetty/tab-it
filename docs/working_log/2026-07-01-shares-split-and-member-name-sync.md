# 2026-07-01 — Split by shares + member name sync after claim

## Goal

Two user-reported gaps from a real trip group chat:

1. **Split by shares** — the app only offers equal and exact splits. Friends
   want share-weighted splitting (e.g. 1 share for a full pint, 0.5 for a
   half). `SplitType.shares` already exists in TabCore and the DB check
   constraint already allows `'shares'`, but the calculator, UI, and sync
   plumbing don't implement it.
2. **Member name sync** — after pre-adding someone to a trip by email, the
   adder keeps seeing the raw email even after that person signs in and gets a
   profile name. The claim path/name propagation is broken somewhere; an
   Explore agent is tracing the exact break.

Constraint: the remote DB now has real trip data (owner is actively using the
app with friends), so remote schema changes must be additive (`alter table`),
not the usual pre-launch destructive reset. Baseline SQL still gets updated so
future recreations match.

## Design decisions

- Persist share weights in a new nullable `expense_splits.share_units`
  column (`numeric(20,8)`, `> 0`, required when `split_type = 'shares'`).
  Without it, editing a shares expense can't restore what the user typed —
  same reason exact amounts round-trip through `amount_owed`.
- Shares allocation: convert total to minor units, give each participant
  `floor(total * share / share_sum)`, then hand out the remaining minor units
  by largest fractional remainder, tie-broken by lexicographically lowest
  UUID. Deterministic, mirrors the equal-split remainder convention.
- UI: `splitMode` gains value 2 (shares) in ExpenseEntryView and
  PaymentSplitDraft. Share inputs accept up to 2 fraction digits regardless of
  currency (shares are not money).

## Update — TabCore + app plumbing done, DB migrated

- `SplitCalculator` implements `.shares` (largest-remainder allocation, UUID
  tie-break); `ExpenseSplit` carries optional `shareUnits`. 140 TabCore tests
  pass (13 new).
- App: `splitMode == 2` is shares in `ExpenseEntryView` + `PaymentSplitDraft`;
  share weights round-trip through `ExpenseSplitEntity.shareUnits`,
  `ExpenseSplitDTO.share_units`, the expense RPC payload, and `SyncMerge`.
  Share inputs use a currency-independent sanitizer (max 2 fraction digits).
- DB: `expense_splits.share_units` added with symmetric check
  (`shares ⟺ share_units not null`, `> 0`); RPC passes it through;
  `sync_profile_name_to_trip_people` trigger propagates profile renames to
  claimed `trip_people` rows; one-time backfill applied. Migration applied
  ADDITIVELY to the live project (real trip data present — no reset).
- All 13 pgTAP suites pass against the live DB.

## Finding — the "friend's name never appeared" case is an unclaimed email

Live data shows every *claimed* member already displays their full profile
name. The two stale rows (`sparshvsk@…`, `sovathna30@…`) were never claimed —
no auth user exists with those emails. An unattached
`…@privaterelay.appleid.com` account exists, so at least one friend likely
signed in via Apple's "Hide My Email", which can never match a pre-added
Gmail. The rename trigger fixes the genuine sync gap; the relay-email case is
an identity-matching product gap (invite links / email change), out of scope
today — surfaced to the owner.

## Update — percentage splits added on top (owner request mid-task)

Owner asked for percentage-based splitting as well. Implemented symmetrically
to shares:

- TabCore: `.percentage` in `SplitCalculator` — validates each percent > 0 and
  the sum == exactly 100, then reuses the same largest-remainder proportional
  allocator as shares (`allocateProportionally`). `equalPercentages(participants:)`
  seeds an equal 100% starting point (extra basis points to lowest UUIDs).
  `ExpenseSplit.percentage` carries the entered value. 146 TabCore tests pass.
- App: `splitMode == 3`; percent fields with a % suffix; footer shows
  "Total 100%" / "X% left" / "Over by X%"; percentages persist through
  `ExpenseSplitEntity.percentage` → RPC → `expense_splits.percentage` → pull.
- DB: `percentage numeric(20,8)` (`> 0 and <= 100`, symmetric type check)
  applied additively to the live project; baseline + pgTAP updated.

## Validation

- TabCore: 146 tests pass.
- App unit tests: 74 pass (7 new draft tests for shares/percentage).
- pgTAP: all 13 suites pass against the live DB (new: share_units/percentage
  schema + constraint tests, RPC round-trips, profile-rename propagation).
- UI tests on iPhone 17 Pro simulator: 6/6 pass, including two new end-to-end
  flows — shares (30 split 1/2/1, detail shows "shares · 3 ways", edit restores
  weights) and percentages (80 split 50/25/25, edit restores percentages).

## Out of scope / follow-ups

- Old TestFlight builds display shares/percentage expenses fine (amounts sync
  as before) but editing one there falls back to exact mode. Friends should
  update before editing those expenses.
- Identity matching for Apple "Hide My Email" sign-ins (pre-added Gmail can
  never match a private-relay address). Needs invite links or an email-change
  flow — product decision, not attempted here.
