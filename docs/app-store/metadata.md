# App Store metadata — tab-it

Copy-paste source for every text field in App Store Connect. Written to the
plain-writing guide (`docs/writing/plain-writing-guide.md`). Character limits
are noted per field; everything here fits.

## App name (30 chars max)

```
tab-it: split trip expenses
```

27 chars. The name field is searchable, so the extra words after "tab-it" earn
their keep. If Apple objects to the colon format, fall back to just `tab-it`.

## Subtitle (30 chars max)

```
keep track of shared expenses
```

29 chars. Same line the app uses on its sign-in screen.

## Promotional text (170 chars max, editable without a new build)

```
Free expense splitting for group trips. Add expenses as they happen, see who owes what, settle up at the end. No ads, no subscription.
```

134 chars.

## Description (4000 chars max)

```
tab-it keeps track of shared expenses on group trips.

Add an expense when it happens: who paid, who's in, done. tab-it works out who owes what and shows one simple balance per person. When the trip's over, settle up and you're square.

It's free. No ads and no subscription. Everything's included. We made it for our own trips because the alternatives kept charging for basics.

WHAT IT DOES

• Equal or exact splits. Two people can pay one bill, and someone who skipped dinner can be left out of that one.
• Per-currency balances. Spend in euros and pounds on the same trip and they stay separate, with no made-up conversion rates.
• Works offline. Add expenses on the plane or up a mountain. They sync when you're back.
• Attach receipt photos to expenses.
• Add people by email. They see the trip when they sign in.
• Push notifications for trip activity, if you want them.
• Settling up records who paid who back, so the trip ends square.

PRIVACY

No ads, no analytics, no selling data. We collect what the app needs to work and nothing else. You can delete your account in the app at any time.

tab-it is open source: github.com/rithwikshetty/tab-it

Questions? support@tab-it.app
```

## Keywords (100 chars max, comma-separated)

```
split,group,travel,bills,settle,owe,iou,money,holiday,friends,cost,balance,vacation
```

83 chars. Words already in the name or subtitle (trip, expense, shared, track)
are left out because Apple indexes those fields too and repeats waste the
budget. Competitor names (Splitwise) are deliberately excluded; guideline
2.3.7 treats other apps' trademarks in metadata as grounds for rejection.

## URLs

| Field | Value |
|---|---|
| Support URL | https://tab-it.app |
| Marketing URL | https://tab-it.app |
| Privacy Policy URL | https://tab-it.app/privacy |

## Categories

- Primary: **Finance**
- Secondary: **Travel**

## Age rating

Answer "No" to everything in the questionnaire. Result: **4+**.

## Copyright

```
2026 Rithwik Shetty
```

## What's New (version 1.3.0)

```
• Join a trip by opening an invite link.
• Open the app, add expenses, and view saved receipts while you're offline. Changes sync when you're back online.
• See how much you lent or borrowed on each expense.
• Amounts now use currency symbols, and you can settle up with fewer payments.
• Trip activity notifications arrive more reliably.
```

## App Privacy section

Already drafted, answer-by-answer: `docs/legal/app-store-privacy-labels.md`.

## Screenshots

Required: one set for the 6.9" display (1320 × 2868 portrait PNG, taken on an
iPhone 16 Pro Max class simulator). Apple scales it down for smaller sizes.
The seeded-simulator screenshots used on the landing page are the right
content; retake them on the 16 Pro Max simulator at full resolution. Suggested
set, in order: trips list, trip detail with balances, add expense, settle up,
activity feed.

## App Review notes (submission form)

Sign-in is required, so App Review will ask how to get in. Suggested note:

```
Sign in with Apple works with any Apple ID and is the fastest way in. Email sign-in sends an 8-digit code to the address entered. No demo account exists because there are no passwords; every account is created on first sign-in.
```

If the reviewer insists on a demo account anyway, that needs a decision at
submission time (the usual route is a reviewer-only email inbox we control).
