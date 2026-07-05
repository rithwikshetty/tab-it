# Member removal + editable person emails

## Goal

Two gaps found while dogfooding the Splitwise import:

1. Imported people get synthetic `<uuid>@users.tab` emails, and the claim flow
   matches on exact email — so imported members can never link to a real
   account. The import sheet even promises "Add their email later so they can
   claim their spot", but no edit-email feature exists.
2. There is no way to remove a member from a trip at all: no UI, no RPC, RLS
   has no delete policy on `trip_people`, and splits/payments/settlements
   restrict-reference `trip_people` so hard deletes are impossible anyway.

Plan: soft removal (`removed_at` on `trip_people`, membership state — not
`deleted_at` semantics, never purged) + `remove_trip_person` and
`update_trip_person_email` RPCs, activity events, and the People sheet UI for
both. Approved direction: removal allowed even with outstanding balances;
history stays intact.

## 2026-07-04 — survey findings

- `private.is_profile_trip_member` is used for two different things: caller
  *access* checks (RPCs, RLS using/with-check) and *creator-identity*
  validation (`expenses.created_by`, `expenses.last_edited_by`,
  `settlements.created_by` in validation triggers and update policies). If it
  becomes strict about `removed_at`, editing or soft-deleting an expense
  created by a since-removed member would be rejected. Splitting into strict
  (access) + lenient `is_profile_trip_member_any` (identity) helpers.
- `add_trip_person_by_email` upserts on `(trip_id, email)` — natural restore
  path: re-adding a removed person's email clears `removed_at`.
- Claim RPC's "already a member of this trip" guard must keep counting removed
  claimed rows, or a re-claim would violate `trip_people_trip_user_uniq`.
- Membership activity trigger is insert/delete only; profile renames update
  `trip_people.display_name` via `sync_profile_name_to_trip_people`, so the new
  update branch must fire only on `removed_at` transitions.
- App sync: trip_people rows are never pushed from the client (RPC-only
  writes); pull reconciliation deletes local people missing from the remote
  set, which still works since removed rows remain selectable to members.
  The removed user themself loses `is_trip_member` → whole trip disappears
  from their pull, and local reconciliation cleans it up.
- Account deletion (`delete_account_data`) left unchanged: sole-member calc
  keeps counting removed claimed rows (conservative; avoids FK surprises).

## 2026-07-04 — DB layer landed

- `trip_people.removed_at` added; `is_profile_trip_member` now strict
  (`removed_at is null`), new `is_profile_trip_member_any` for creator/editor
  identity validation (`expenses.created_by`, `expenses.last_edited_by`,
  `settlements.created_by`, and both RLS update with-checks).
- New RPCs `update_trip_person_email` (pending, non-removed people only;
  friendly 23505 on in-trip duplicates) and `remove_trip_person` (soft,
  idempotent, self-removal blocked, non-group rejected via kind filter).
- `add_trip_person_by_email` restores removed people on email conflict; claim
  skips removed rows (but its dup-guard still counts them, avoiding a
  `trip_people_trip_user_uniq` violation on re-claim); suggestions exclude
  removed rows; push fan-out and unread badge exclude removed members.
- Found + fixed a leak: a removed trip creator could still rename the trip by
  re-running `create_trip_with_self` (guard trusted `created_by`); the guard
  now requires active membership or a truly-unremoved creator.
- Membership activity trigger handles updates: `member_left` on removal,
  `member_joined` on restore; claims/email edits/name syncs stay silent.
- Baseline rebuilt; new `supabase/tests/14_membership_management.sql`
  (30 tests: allow + deny paths, access revocation, ledger integrity for
  removed members, restore, claim/suggest guards, push exclusion). Recreated
  the linked dev DB; all 14 pgTAP suites pass.

## 2026-07-04 — app layer landed, all green

- `TripPersonEntity.removedAt` + `TripEntity.activePeople`; `removed_at`
  through `TripPersonDTO` and both SyncMerge branches. New
  `SyncService.updateTripPersonEmail` / `removeTripPerson` (RPC-backed, merge
  the returned row; local-only mutation under DEBUG mock auth).
- People sheet: rows are tappable (except "You") and open a PersonDetailSheet
  (medium detent) with email repointing for pending people and soft removal
  with a confirmation dialog. Placeholder `@users.tab` emails render as
  "No email yet" with a "No email" badge — raw UUID emails never shown.
- Picker policy: member cards/avatar groups and default participants use
  `activePeople`; ExpenseEntry/PaymentSplit include removed people already
  referenced by the expense being edited; SettleUp includes removed people
  with nonzero balances (ghost debts stay settleable); Friends shows removed
  people only while something is still owed. Display-name lookups stay on
  `people` so history keeps resolving.
- Confirmation dialog action renamed "Remove" (its original "Remove from
  trip" label collided with the sheet button in accessibility space).
- New `TripPeopleFlowUITests` covers remove → row disappears, email edit →
  new email visible, and removed member absent from the paid-by picker.
  Registered by regenerating the project (`cd Apps/Tab && xcodegen generate`
  — pbxproj is gitignored/generated, not hand-edited).
- Full suite: 97/97 pass (had to `simctl erase` the iPhone 17 Pro sim once —
  repeated "Busy / failed preflight checks" launch errors are sim-state
  corruption, not app failures). Screenshots from the UI test confirmed
  layout: no overflow, correct badges, removed member gone from header
  avatars.
