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

• Split equally, by exact amounts, by shares or by percentages. Two people can pay one bill, and someone who skipped dinner can be left out of that one.
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

## What's New (version 2.0.1)

```
Fixes and a smoother app.

• Balances are exact when several people pay one bill.
• Long trips and a busy Activity feed scroll smoothly.
• A trip renamed while offline keeps its new name.
• A receipt photo you remove is erased from our servers about 30 days later.
• Fixes to Splitwise import, signing out while offline and syncing.
```

## App Privacy section

Already drafted, answer-by-answer: `docs/legal/app-store-privacy-labels.md`.

## Screenshots

One set for the 6.9" display (1320 × 2868 portrait PNG). Apple scales it down
for smaller sizes. The set is in `docs/app-store/screenshots/`, in upload
order:

| File | Screen |
|---|---|
| `01-trips.png` | Trips list with three trips in three currencies |
| `02-trip.png` | Trip detail with the balance card and timeline |
| `03-add-expense.png` | New expense with an equal split |
| `04-settle-up.png` | Record a payment |
| `05-friends.png` | Friends, balances per person |
| `06-activity.png` | Activity feed |

To retake them:

1. `bash supabase/scripts/reset_local.sh`, then load
   `docs/app-store/screenshots/demo-data.sql` (the command is at the top of
   that file). Every name and amount in it is made up.
2. Run a development build on an iPhone Pro Max simulator and sign in as
   `mock@tab.local`.
3. Set the status bar with
   `xcrun simctl status_bar <udid> override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4`.
4. Capture each screen at device resolution.

## App Review notes (submission form)

Sign-in is required, so App Review will ask how to get in. Suggested note:

```
Sign in with Apple works with any Apple ID and is the fastest way in. Sign in with Google works with any Google account. Email sign-in sends an 8-digit code to the address entered. No demo account exists because there are no passwords; every account is created on first sign-in.
```

If the reviewer insists on a demo account anyway, that needs a decision at
submission time (the usual route is a reviewer-only email inbox we control).
