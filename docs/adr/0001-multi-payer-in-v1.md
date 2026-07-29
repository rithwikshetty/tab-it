# ADR-0001: Multi-payer expenses

## Status

Accepted — 2026-05-18

Historical note — 2026-07-29: this ADR records the pre-production conditions
under which the decision was made. Production now contains real users; its
destructive database assumptions and commands are no longer valid.

## Context

`PRD.md` line 198 lists *"Multiple payers per expense"* as explicitly out-of-scope, deferred to a later phase. The original schema modelled the payer as a single column on the expense row:

```
expenses.payer_id : UUID
```

During the design grill for the expense-entry flow, the user's actual mental model surfaced: a real trip expense routinely has **multiple payers** (e.g., A and B split a €250 dinner check 100/100/50). Treating that as V2 would force one of two bad outcomes:

1. **Log as multiple distinct expenses, one per payer.** Breaks the "one bill, one expense" mental model — each fragment has its own receipt-attachment, category, description. Doubles or triples the entry effort. Pollutes the activity log.
2. **Defer and rewrite later.** Before production this was cheap; after release
   it would require a carefully migrated change across live data and installed
   clients.

At the time of this decision, tab had not entered production, so wholesale
schema replacement was still possible. That condition no longer applies. The
cost of adopting multi-payer then was mechanical schema work plus a
balance-engine refactor; the cost of deferring would have become permanent
data-model debt once real users existed.

## Decision

Adopt multi-payer from the start.

### Data model
- Drop `expenses.payer_id`.
- Add table `expense_payments`:
  ```
    expense_payments
    expense_id    uuid  fk -> expenses(id)
    trip_person_id uuid fk -> trip_people(id)
    amount_paid   numeric(20, 4)
    payment_mode  text     -- 'equal' | 'exact' (mirrors split_type values)
    PRIMARY KEY (expense_id, trip_person_id)
  ```
- DB trigger enforces `sum(amount_paid) on active expense = expenses.amount`, mirroring the existing trigger for `expense_splits`.
- RLS: user can read/write payments iff they have a joined `trip_people` row for `expenses.trip_id`. Mirrors the policy for splits.
- Payer references are constrained to `trip_people` rows for the expense's trip — matches the existing constraint pattern for participants, payers, and settlement parties.

### Domain shape
- An [[Expense]] now carries **two independent ledgers**:
  - **Payment ledger** (who fronted cash) — set of [[Payment]] rows.
  - **Split ledger** (who is on the hook) — set of [[Split]] rows (`expense_splits`, unchanged).
- Both ledgers independently invariant: each sums to `expense.amount`.
- Single-payer is just `N=1` row in `expense_payments` — no special-casing in code.

### Pure-logic modules
- `SplitCalculator` is unchanged. It computes splits, not payments.
- A small helper (or extracted shared routine) computes the equal-mode distribution for either ledger — same deterministic 1-cent remainder algorithm (lex-lowest UUIDs first).
- `BalanceEngine` refactors to consume both `expense_payments` and `expense_splits`. Per-person net per expense = `sum(payments by trip person) - sum(splits owed by trip person)`. Pair-balance aggregation across expenses + settlements is otherwise unchanged.

### UX (locked during the same design session — see also `design/expense_entry_flow_mockups.html`)
- Main expense-entry form remains a single scroll.
- "Paid by" is a row on the main form. Default state shows the recorder (current user) as the sole payer.
- Tap → pushes a dedicated sub-page (Variant B in the mockups) containing:
  - Total readout (read-only),
  - Mode segmented (Equal | Exact) — mirrors the split UX,
  - Per-member rows with selection checkbox + per-row amount field (Exact mode) or auto-derived amount (Equal mode),
  - Reconcile footer (✓ reconciles / Remaining X / Over X).
- "Done" pops back; main row reads `"N people · TOTAL CCY"`.
- Default for new expense: recorder only, Equal mode, full amount. Single-payer users never visit the sub-page.

### Validation
- Save is gated by `sum(payments) = sum(splits) = expense.amount` (and the existing required fields).
- Mismatch in either ledger renders the corresponding row red on the main form and disables Save. No silent rescaling of typed values; Equal-mode entries auto-redivide on total change, Exact-mode entries are left untouched and surface the mismatch.

## Consequences

- At the time of this decision, the pre-production schema was recreated. That
  historical workflow must not be used against the current production system.
- `PRD.md` line 198 must be removed from out-of-scope; the user-stories section gains a story for multi-payer entry.
- New TabCore tests:
  - Payment-ledger Equal/Exact parity with split-ledger tests.
  - `BalanceEngine` cases: A paid, B owes (current); A+B paid, A+B+C owe (new); cross-currency unchanged.
- The SwiftData entity layer in the iOS app changes: `ExpenseEntity` loses `payerID` and gains a `payments: [PaymentEntity]` relationship.
- Sync engine: `expense_payments` becomes a synced table with its own pending-changes queue, realtime channel, conflict resolution (LWW + delete-wins like other mutable tables).

## Alternatives considered

- **Keep `payer_id`, add `expense_payments` only when N > 1.** Two sources of truth — `null` payer_id meaning "see table". Reads branch. Rejected.
- **Store payments as JSON column on `expenses`.** Cheap migration, but loses DB-enforced sum invariant, RLS granularity, and queryability for future "expenses where I paid" views. Rejected.
- **Model each payment as a separate expense row grouped by `parent_id`.** Most general (could absorb sub-receipts). Rewires balance engine and UI completely for an edge case. Rejected as overkill.
- **Defer to a later phase.** See Context — would force a complex live-data and
  client migration after release. Rejected.
