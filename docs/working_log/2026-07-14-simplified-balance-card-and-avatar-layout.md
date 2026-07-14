# Simplified balance card + avatar layout fixes

## Goal

Two UX changes requested by Rithwik:

1. The trip detail top balance card must always reflect **simplified debts**, never
   the raw pairwise ("general") balances. Total on top, then per-person rows
   derived from the simplified repayments.
2. Fix the "You owes X" grammar in the Balances tab.
3. Avatar layout: cap avatars in the trips list rows; fix the trip-detail header
   where the dashed add-person button overlapped under the "+N" overflow badge
   and the group squeezed/cut the trip title.

## 2026-07-14 — decisions

- Asked whether the Balances tab's simplified debts card should stay once the top
  card shows simplified debts. Decision: **keep it** — it still shows debts
  between other members and hosts the tappable Settle up rows.
- Header avatars move to the navbar centre (`ToolbarItem(placement: .principal)`),
  between the back button and the ellipsis menu, per Rithwik's suggestion. Shows
  up to 3 avatars + "+N" + the add button; the title keeps the full content width.

## 2026-07-14 — changes

- `BalancePresenter.summaries` (EntityViewState.swift): detail rows now come from
  `DebtSimplifier.simplify(...)` filtered to debts involving the current person,
  instead of raw `BalanceEngine` pairwise entries. Headline net per currency is
  unchanged (simplification preserves net positions). Sorting kept: amount desc,
  then name, then UUID.
- `TripDetailView.balancesSection`: verb is now `owe` when the row's semantic is
  `.borrowed` (the current user is the debtor), fixing "You owes Alex".
- `AvatarGroup` (Avatar.swift): the add button moved outside the overlapping
  `spacing: -8` stack into a `spacing: 5` slot — the dashed ring has no opaque
  fill, so overlapping it under the overflow badge let the badge show through.
- `TripDetailView`: header `AvatarGroup` moved from the title HStack to a
  `.principal` toolbar item (size 30, `maxVisible: 4`); title now takes the full
  width.
- `TripCardRow`: `maxVisible: 4` so long member lists collapse to 3 avatars +
  "+N" in the trips list.
- Tests: added `summaryDetailsUseSimplifiedDebts` to BalancePresenterTests —
  a debt chain (You→Sam 30, Sam→Alex 30) must surface as "You owe Alex" on the
  top card.

## Validation

- `xcrun swiftc -parse` on all edited files: clean.
- No Xcode build/simulator testing per request — Rithwik will verify in Xcode.

## 2026-07-14 21:50 BST — commit preparation

- Reviewed all six changed/untracked files as one cohesive UX change.
- `git diff --check`: clean.
- Kept the work as a single feature commit because the balance presentation,
  grammar fix, avatar layout adjustments, regression test, and this log all
  belong to the same requested trip-detail polish.
