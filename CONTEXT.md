# Context — tab

A multi-user, multi-currency group expense tracker for trips. iOS-first, offline-first, private friend-group use; no monetisation.

The current model covers trips, members, expenses (trip-bound and [[Non-group expense|non-group]]), multi-payer payment ledgers, split ledgers, pairwise balances, [[Simplified debt|simplified trip debts]], settlements, categories, receipt photos, trip export, a per-trip spend [[Overview]], and a cross-trip per-person debt view ([[Friends]]). The server contract also includes an activity log, push devices, and trip mute preferences. Not in scope: itinerary, cross-trip *spend* analytics, payment-app links, currency conversion, Android, or percentage/share split UI.

This file is the project's domain glossary. Only terms meaningful to a domain expert (someone reasoning about expenses, balances, and trips) belong here — implementation specifics live in code.

## Glossary

### Profile
The account-level identity for a signed-in user: display name plus optional avatar. A Profile is not the ledger identity inside a trip; that role is [[Trip person]].

### Trip
A container of trip people, expenses, settlements, categories, activity, and per-user notification preferences. A user can belong to many trips through one joined [[Trip person]] row per trip. State (`active` vs `completed`) is **derived, not stored** — see [[Active / Completed trip state]].

### Trip person
A trip-scoped ledger identity identified by normalized email and display name. It may already be linked to a [[Profile]], or it may be pending until someone signs in with that email. Expenses, payments, splits, and settlements reference trip people so a trip can be planned before every person has opened the app.

### Trip member
A joined trip person: one whose email has been claimed by a signed-in Profile. Trip access is derived from joined trip people. A joined member can inspect all expenses, payment shares, split shares, and debts inside that trip, including rows belonging to pending trip people who do not use the app. This visibility never crosses into another trip. Pending trip people can still appear in ledgers, but they do not grant app access until claimed.

### Email pre-add
Adding a trip person by email before that person has signed in. If the email already belongs to a Profile, the trip person joins immediately. Otherwise it remains pending and is automatically claimed when someone signs in with the same normalized email. There is no global user search; suggestions are limited to people the current user has already shared trips with.

### Category
The expense classification shown on expense rows and exports. Categories are either built-in defaults (`Food & Drink`, `Transport`, `Lodging`, `Activities`, `Shopping`, `Other`) or custom trip-scoped categories. An Expense can use a default category or a category belonging to the same trip.

### Receipt photo
An optional JPEG attached to one Expense. Receipts are private to trip members and are addressed by trip/expense ownership, not by a public URL.

### Expense
A single shared cost. Either **trip-bound** (incurred on a [[Trip]]) or a [[Non-group expense]] (no trip). Has one positive amount, one ISO currency, one description, one expense date, one category, one payment method, optional receipt photo, and **two ledgers**: [[Payment ledger]] and [[Split ledger]]. Each ledger independently sums to `expense.amount`.

Expense creation/editing is atomic at the domain boundary: the expense row, payment ledger, and split ledger must be saved together so a saved active expense is always balanced.

### Non-group expense
An [[Expense]] not attached to any [[Trip]] — a casual cost split with people without first creating a trip. Identical in every other way to a trip-bound expense: multiple participants, multi-payer, email [[Email pre-add|pre-add]], the two ledgers, soft delete. It uses the same ledger identity ([[Trip person]]) and the same balance math; it is not surfaced in the Trips list but appears under [[Friends]] and in each involved person's [[Overall balance]]. Settlements against a non-group balance are recorded in the non-group context, not in any trip.

**Visibility is per participant set:** a non-group expense is visible to exactly the people on it, and never to anyone else — splitting dinner with one friend and a cab with another keeps each private to its own pair. Mechanically each distinct set of people gets its own hidden, automatically-managed context (see `docs/adr/0003`); this is invisible to the user, who simply "adds an expense with these people".

### Payment method
How the expense was paid at a high level: `cash`, `card`, or `bank_transfer`. This is separate from [[Payment mode / Split mode]], which describes how ledger amounts are allocated across people.

### Payment ledger
Set of [[Payment]]s on one [[Expense]]. Invariant: `sum(payment.amount_paid) = expense.amount`. Records *who actually fronted cash*.

### Payment
A single trip person's contribution toward an Expense. Has trip person, non-negative amount paid, and mode (`equal` or `exact`).

### Payer
A trip person represented in the Payment ledger for a given Expense. An Expense always has at least one Payer. Multi-payer is supported.

### Split ledger
Set of [[Split]]s on one [[Expense]]. Invariant: `sum(split.amount_owed) = expense.amount`. Records *who is on the hook for the cost*.

### Split
A single trip person's owed share of an Expense. Has trip person, non-negative amount owed, and mode (`equal` or `exact`).

### Participant
A trip person with ≥ 1 Split on a given Expense. May or may not also be a Payer.

### Payment mode / Split mode
- `equal` — total auto-divided across selected users. 1-cent remainders are distributed to lex-lowest UUIDs (deterministic, see `SplitCalculator` / `PaymentCalculator`).
- `exact` — user enters per-user amount directly. Sum must equal total.
- Additional enum values (`percentage`, `shares`, `adjustment`) exist in the schema but are not yet supported by the UI or TabCore calculators.

### Net per trip person per expense
`net = sum(payments by trip person) - sum(splits owed by trip person)`.
Drives [[Pair balance]] aggregation. Sums to zero across all trip people on a single expense (because both ledgers sum to `expense.amount`).

### Pair balance
Per `(trip_person_pair, currency)` balance derived from all expense nets plus settlements within a trip. This is the raw, history-preserving source of truth computed by `BalanceEngine`; it is not mutated when the UI presents [[Simplified debt]]s.

The canonical pair key sorts the two trip-person UUIDs `(lo, hi)`. Positive canonical amount means `hi` owes `lo`. External presentation uses mirrored [[User balance]] rows.

For a multi-payer expense, each debtor's shortfall is allocated across creditors in proportion to each creditor's surplus. Settlements then subtract from the relevant pair/currency balance.

### Simplified debt
A derived repayment suggestion that reduces the number of payments needed to clear one trip while preserving every trip person's net position. Simplification runs independently per trip and per currency, may suggest repayment between people who did not transact directly, and is deterministic for equal positions. It never crosses trips or currencies and never rewrites the underlying [[Pair balance]], expenses, ledgers, or settlements. Recording a suggested payment creates a normal [[Settlement]].

### User balance
The user-facing mirror of a [[Pair balance]]: `forUser`, `withUser`, `currency`, `amount`. Positive amount means `withUser` owes `forUser`; negative amount means `forUser` owes `withUser`.

### Overall balance
The net of all [[User balance]]s between the current user and one other person, **per currency**, summed across every shared [[Trip]] plus the [[Non-group expense]] context. Surfaced on [[Friends]]. It is **derived, never stored** and is not its own ledger: there is no global "settle everything". [[Settle up]] always targets a single source (one trip, or the non-group context); the overall balance changes only as a consequence. Currencies are never blended (no FX) — each currency is its own line.

### Settlement
A recorded payment of money from one trip person to another outside the app. Has from-person, to-person, positive amount, currency, optional note, and settled-at date. Any trip member can record a settlement between any two trip people in that trip.

Settlements are independent of [[Expense]]s: they do not mutate expenses or ledgers. They only contribute to balance aggregation. A settlement can partially reduce a debt, clear it, overpay it, or move the pair balance in the opposite direction.

### Settle up
The user workflow for creating or editing a Settlement. When suggesting defaults, the app first prefers a debt the current person owes, then a debt another person owes the current person. A settlement always targets a **single source** — one [[Trip]] or the [[Non-group expense]] context. Launched from [[Friends]], the user first picks which source to settle (there is no blended cross-source settle); the [[Overall balance]] then updates as a consequence.

### Active / Completed trip state
A trip is **Completed** when its derived [[Simplified debt]] set is empty across all currencies and `lastActivityAt` is at least 30 days old. Otherwise it is **Active**. Raw pair balances may still contain a fully cancelling cycle; that cycle requires no repayment and therefore does not keep the trip active.

The activity clock starts at trip creation and is bumped by expense or settlement writes, including edits/deletes. A new expense or settlement on a Completed trip reactivates it. State is derived from data; never stored.

### Currency
A trip-level concept only in the sense that each expense and settlement carries its own ISO currency code. **No FX conversion**. Totals, balances, and exports are computed and displayed strictly per currency.

### Overview
A per-trip, read-only summary of **spend** — what the trip cost and how that cost is distributed. Scoped to one currency at a time (see [[Currency]]); a currency picker selects which when a trip has more than one. Shows total trip spend, the current user's *paid* and *share* totals, a per-person breakdown (both paid and share), and a per-category breakdown. **Settlements are excluded entirely** — a settlement is debt-clearing, not trip cost, so it never appears in any Overview total or chart. Distinct from the Balances tab, which answers debt (who owes whom, settlements included); Overview never shows net-owed. Surfaced as a third segment alongside Expenses and Balances on the trip detail screen.

"Spend" splits into two figures, never blurred:
- **Paid** — what a trip person fronted (from the [[Payment ledger]]).
- **Share** — what a trip person consumed / is on the hook for (from the [[Split ledger]]).
Both are shown so neither sense of "who spent the most" is hidden. Total trip spend = `sum(active expense.amount)` per currency and equals both the summed paid and summed share.

### Timeline
The visible trip activity stream, grouped by date, containing active expenses and active settlements in reverse chronological order.

### Activity log
An append-only table for trip actions such as expense changes, settlement changes, membership events, and trip changes. This is separate from the visible [[Timeline]].

It is the **single shared event stream** behind notifications: one row per event (not one per recipient), readable by all trip members. Both notification channels render from it — the in-app [[Activity]] feed and the [[Push notification]] channel. Targeting ("is this for me"), self-exclusion, and read/unread are derived per user at read time, never duplicated into per-recipient rows.

### Activity
The user-facing rendering of the [[Activity log]]: an **app-level (global)** feed surfaced as a bottom tab (Friends · Trips · Activity · Settings), shown on the tab roots and on trip detail, hidden on deeper/entry screens. It shows events across *all* the current user's trips, newest first (date-grouped). Your own actions still appear as history, but are **never marked unread** (you are never *notified* of what you did — no badge, no highlight). It is the only surface that can announce a trip the user has not yet opened — e.g. being added to a brand-new trip. Distinct from the per-trip [[Timeline]] (a single trip's expenses + settlements) and from the [[Overview]] (spend summary).

Read state is a **single per-user `last_seen_at` cursor** (synced, multi-device). Unread = events newer than the cursor, with `actor != me`, on non-muted trips (see [[Trip mute preference]]). Opening the Activity tab advances the cursor to now and clears the badge; opening an individual trip does not. The same count drives the tab badge and the app-icon badge.

### Friends
The first bottom tab (Friends · Trips · Activity · Settings): a per-person, cross-trip debt view. Lists every person the current user shares a non-zero [[Overall balance]] with, netted across all trips and the [[Non-group expense]] context, per currency. Tapping a person opens a detail that breaks the overall balance back out **by source** (non-group + each trip) and shows a unified history of every shared expense and settlement, each row tagged with its origin. [[Settle up]] from here is per-source (see [[Overall balance]]). Distinct from the per-trip Balances surface, which answers debt *within one trip*. Answers debt only — spend lives in [[Overview]].

### Push notification
The APNs channel: an OS-level banner delivered to a member's [[Push device]]s when a trip event occurs, even with the app closed. Same source and same targeting rules as the [[Activity]] feed (members of the trip, minus the actor, minus those who set a [[Trip mute preference]]). Recipient device tokens are selected server-side at send time; no per-recipient row is stored. Current policy: **every** [[Activity log]] action type fires a push (tunable later in the sender, no schema change). Banners are rich (actor + amount + description; trip name as title); lock-screen privacy is left to iOS's native "Show Previews" setting. Pushes are grouped natively by trip via APNs `thread-id`; rapid re-edits of one entity collapse via `apns-collapse-id`. The send payload also carries the recipient's current unread count as `aps.badge` so the app-icon badge stays correct with the app closed.

### Soft delete
Mutable user-visible records are deleted by setting `deleted_at`, not by immediate hard delete. Active domain calculations ignore soft-deleted expenses and settlements. The server-side purge window is 30 days.

### Trip mute preference
A per-user, per-trip notification preference. Row presence means the trip is muted for that user; absence means unmuted. Semantics are **silence, don't hide**: a muted trip stops sending [[Push notification]]s and stops contributing to the unread badge, but its events still appear in the [[Activity]] feed so the user can catch up deliberately.

### Push device
A user's registered APNs device token. Push devices are account-scoped, not trip-scoped; trip notification behavior is controlled by [[Trip mute preference]]. Permission is requested on first launch after sign-in; the token is re-registered and upserted on **every** launch so reinstalls and token rotation self-heal. Dead tokens (APNs `410 Unregistered`) are deleted server-side by the sender. APNs never replays missed banners on reinstall — the [[Activity]] feed carries the missed history instead.

### Trip export
A spreadsheet-style export for a trip. It includes active expenses, payment rows, split rows, settlements, totals by currency, per-person paid/owed summaries, and pair balances.

## Adopted decisions

Significant decisions live as ADRs under `docs/adr/`. Current set:

- `0001-multi-payer-in-v1.md` — multi-payer expenses adopted into the initial design.
- `0002-notification-architecture.md` — shared-row event sourcing via DB triggers; DB webhook → edge function → direct APNs; per-user read model. Feeds the [[Activity]] feed and [[Push notification]] channel.
- `0003-non-group-expense-model.md` — [[Non-group expense]]s live in hidden `trips` rows deduplicated per participant-set (shadow groups), so the existing container-scoped RLS + ledger identity + balance math are reused unchanged; [[Overall balance]] is a pure cross-container aggregation.
