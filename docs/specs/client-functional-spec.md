# Client functional specification

This is the behaviour checklist for the tab-it app in `mobile/`: one Expo / React Native app for iOS and Android. It says what every screen does, what happens in the background, and which server rules the app depends on. Use it to learn the app, and to check that a change didn't break something.

Each bullet ends with the code that implements it. Paths are from the repository root, and a symbol or line number follows when the file is large. When this document and the code disagree, the code is right and this document needs fixing. Things that look like bugs rather than intent are listed under [Open questions](#open-questions).

Words like trip person, non-group expense, simplified debt and overall balance are defined in `CONTEXT.md`. As in the app, "payment" here means a settlement (money recorded as changing hands); the rows saying who paid for an expense are "expense payments" or the payer ledger. The pure domain functions are listed in `mobile/src/domain/API.md`.

## Screens and flows

Screens appear in the order a user meets them.

### App start

- A build without `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY` shows "No backend configured" and nothing else. Nothing falls back to a hosted project. `mobile/src/app/_layout.tsx` (`MissingConfig`), `mobile/src/lib/config.ts`
- The splash screen stays up until the session is known. Signed-out users see sign-in. Signed-in users see the tabs. The join and auth-callback routes work in both states. `mobile/src/app/_layout.tsx` (`RootNavigator`)
- If a signed-in user's local store can't be opened, the app shows "Couldn't open your trips" with "Try again", which reopens the store, and "Sign out", which takes this phone off the account's notifications, drops the saved session and leaves the data on the phone. `mobile/src/app/_layout.tsx` (`StoreFailed`), `mobile/src/data/session.tsx` (`SessionProvider`)
- Startup first reads the saved Supabase session (10 second limit). With none, it tries the session the older iOS app left in the Keychain (see [Legacy handoff](#legacy-handoff)). Any failure lands on sign-in. `mobile/src/data/legacy/startup.ts` (`loadSession`)
- The session is saved in SecureStore, split into chunks in one of two slots. A write fills the other slot and moves the pointer last, so a write that is cut short keeps the previous session. A session saved by a build up to 2.0.0 is read from its older layout and moved on the next write. `mobile/src/lib/supabase.ts` (`secureStorage`)
- Once signed in, the app opens that user's local database, imports any older iOS app data, deletes receipt photos nothing refers to, then starts the sync engine. The tabs appear only after the store is open. `mobile/src/data/session.tsx` (`SessionProvider`)
- The signed-in user's name comes from auth metadata `display_name`, then `given_name`, `full_name`, `name`, then the email's local part, then "You", cut to 60 characters. Once the profile row has synced, its name is used instead. `mobile/src/data/session.tsx` (`currentUserFrom`, `useMyName`)
- The app is light-mode only and portrait only. iOS doesn't support iPad layouts. `mobile/app.config.ts`

### Sign-in

- The screen shows the "tab-it" wordmark and "keep track of shared expenses". `mobile/src/app/sign-in.tsx`
- Sign in with Apple shows only on iOS, and only when the device supports it. `mobile/src/app/sign-in.tsx` (`appleAvailable`)
- "Continue with Google" shows only when the build sets `EXPO_PUBLIC_GOOGLE_SIGN_IN=1`. `mobile/src/lib/config.ts` (`googleSignIn`)
- Below an "or" divider is the email form: "Full name", "Email address", "Send email code", and "We'll email you a {n}-digit code to sign in. No password needed." Send is enabled when both fields are non-blank and nothing is in progress. The code length `n` is `EXPO_PUBLIC_EMAIL_CODE_LENGTH`, default 8. `mobile/src/app/sign-in.tsx`, `mobile/src/data/auth.ts` (`EMAIL_CODE_LENGTH`)
- Sending checks the name (trimmed, at most 60 characters, else "Enter your full name.") and the email (trimmed and lowercased, exactly one "@", a non-empty local part, a domain with a dot, no spaces, else "Enter a valid email address."). `mobile/src/data/auth.ts` (`sendEmailCode`, `normalizeEmailInput`)
- When the build has a Turnstile site key, every send and resend first opens the "Quick check" sheet ("Confirming you're a person, not a bot.", "Cancel"). The widget runs in a web view whose base URL is `https://tab-it.app`. A token sends the code once. Cancel returns to the form. A widget failure shows "The check didn't load. Try again." An expired challenge resets itself. Each opening mounts a fresh widget, so every send gets a new token. `mobile/src/features/auth/turnstile.tsx`, `mobile/src/app/sign-in.tsx` (`requestCode`)
- The code request asks Supabase to create the user if needed, passes the auth callback URL, the captcha token, and the name under `display_name`, `full_name` and `name`. After a successful send the name is saved under `auth.pendingName` in SecureStore. `mobile/src/data/auth.ts` (`sendEmailCode`)
- After sending, the form becomes "Enter your code", "We sent a {n}-digit code to {email}.", a code field, "Verify code", "Resend code" and "Change email". The field keeps digits only, stops at `n` digits, offers one-time-code autofill and verifies by itself when the last digit arrives. "Change email" clears the code and the status. Success messages are "Code sent. Check your email and enter it here." and "New code sent." `mobile/src/app/sign-in.tsx`
- Verification needs a returned session, else "We verified the code but couldn't start a session. Request a new code and try again." If the saved pending name belongs to this email, it's written to auth metadata. The saved name is then deleted. `mobile/src/data/auth.ts` (`verifyEmailCode`)
- Server errors are rewritten: an expired or invalid code shows "That code is wrong or has expired. Request a new one.", a rate limit shows "Too many attempts. Wait a minute, then try again.", a captcha failure shows "The security check failed. Try again." Other messages show as they come. Errors appear under the form in red with an error haptic. `mobile/src/data/auth.ts` (`friendlyAuthError`), `mobile/src/app/sign-in.tsx` (`run`)
- Apple sign-in asks for full name and email, sends Apple a SHA-256 hashed nonce and Supabase the raw nonce with the identity token. A missing token shows "Apple didn't return an identity token." When Apple shares a name, it's saved to auth metadata. `mobile/src/data/auth.ts` (`signInWithApple`)
- Google sign-in is native on iOS with a nonce-bound ID token. On Android it opens the system browser and exchanges the returned code. Cancelling Apple or Google returns to the form with no error. "Signing in…" shows while either runs. `mobile/src/data/auth.ts` (`signInWithGoogle`)
- Development builds pointed at the local Docker stack show one-tap sign-in chips for `mock`, `alex` and `sam`. Password sign-in refuses any other backend. `mobile/src/app/sign-in.tsx` (`LocalSignIn`), `mobile/src/data/auth.ts` (`signInWithLocalPassword`)
- "Privacy policy" opens `https://tab-it.app/privacy` in an in-app browser. `mobile/src/app/sign-in.tsx`

### Links into the app

- `https://tab-it.app/join/<token>` and `com.rithwikshetty.tab://join/<token>` open the join route. It lowercases the token, keeps it only if it's 32 hex characters, saves it in SecureStore under `invite.pendingToken`, and goes to the app's start. The signed-in shell redeems it (see [Invites, claims and membership](#invites-claims-and-membership)). `mobile/src/app/join/[token].tsx`, `mobile/src/data/invites.ts`
- `com.rithwikshetty.tab://auth-callback?code=…` finishes a sign-in that returns outside the in-app browser session. While the Android Google browser sign-in is running, that flow exchanges its own code and this route does nothing. A failed exchange shows "Couldn't sign in" and "That sign-in link didn't work. Ask for a new code and try again." `mobile/src/app/auth-callback.tsx`, `mobile/src/data/auth.ts` (`browserSignInRunning`)

### Signed-in shell and tabs

- Four tabs in this order: Friends, Trips, Activity, Settings. Trips is the index route, so the app's start (`/`) is the Trips tab. `mobile/src/app/(app)/(tabs)/_layout.tsx`
- The Activity tab shows the unread count as a badge, capped at "99+". `mobile/src/app/(app)/(tabs)/_layout.tsx`, `mobile/src/features/activity/use-unread.ts`
- These screens open as modals: New trip, New expense, the expense form, Record a payment, People, Import from Splitwise, Edit trip and Unsynced changes. Trip, expense, payment and friend details push onto the stack. `mobile/src/app/(app)/_layout.tsx`
- The shell redeems pending invites, registers for push, keeps the app icon badge equal to the unread count, pulls when a push arrives in the foreground and opens the right screen when a push is tapped. `mobile/src/app/(app)/_layout.tsx` (`usePendingInvite`, `usePush`)

### Shared presentation rules

- Money shows the currency's symbol followed by the amount with en-US grouping and exactly the currency's minor-unit digits, for example `€1,234.50` or `¥1,250`. When the symbol is the code, it shows `CODE 1,234.50`. A negative amount puts "-" before the symbol. Different currencies are never added together. `mobile/src/domain/money-formatter.ts` (`formatMoney`)
- People lists put the current person first, then joined people before pending ones, then names compared case-insensitively with accents ignored first. The current person shows as "You", but their avatar uses their real name. `mobile/src/domain/presentation-helpers.ts` (`sortedPeople`, `compareNames`)
- An avatar shows the first character of the trimmed name in upper case, or "?". Its colour is one of terracotta, sage, sand or slate, picked from the byte sum of the account's user id (joined people), the email (pending people) or the person id, so one person has one colour in every trip. Avatar groups show up to four; with more, they show three and "+{rest}". `mobile/src/domain/presentation-helpers.ts` (`personTone`, `avatarInitial`), `mobile/src/ui/avatar.tsx` (`AvatarGroup`)
- The six built-in categories, in order, are Food & Drink, Transport, Lodging, Activities, Shopping and Other. Their ids are `0000000N-0000-0000-0000-000000000000` for N = 1 to 6 and their icons `bowl-food`, `car-profile`, `bed`, `mask-happy`, `shopping-bag` and `tag`. Each has its own tint. A category whose icon isn't one of these draws the tag icon. `mobile/src/domain/presentation-helpers.ts` (`DefaultCategories`), `mobile/src/ui/category-icon.tsx`, `mobile/src/ui/theme.ts` (`categoryTones`)
- Haptics: light for row taps, avatar add and primary buttons; medium for the floating Add expense button; selection for chips, toggles and pickers; success after a save, delete or import; warning when Save is tapped with problems; error on failed sign-in, email save or invite join. `mobile/src/ui/haptics.ts`, `mobile/src/ui/primitives.tsx`
- Trips, Friends and trip detail show a sync banner. With refused changes it says "1 change couldn't be saved." or "{n} changes couldn't be saved." with a "Review" button that opens Unsynced changes. Offline it says "Offline. {n} change(s) will sync when you reconnect." or "Offline. Showing what's saved on this phone." `mobile/src/features/sync/sync-banner.tsx`
- The currency picker is a sheet titled "Currency" with "Done", a "Search code or name" field and rows of symbol, code and name, with a check on the current one. Tapping a row picks it and closes the sheet. Closing without picking keeps the old value. `mobile/src/features/currency/currency-picker.tsx`

### Trips tab

- The title is "Trips", with a "+" button that opens New trip. Pull to refresh runs a full sync. `mobile/src/app/(app)/(tabs)/index.tsx`
- It lists live trips of kind `trip` where the user has a person row that isn't removed, newest `last_activity_at` first, split into "Active" and "Completed". Non-group containers never appear here. `mobile/src/app/(app)/(tabs)/index.tsx`, `mobile/src/data/selectors.ts` (`liveTrips`, `myPeopleByTrip`)
- Each card shows the trip name, the active members' avatars (up to four) and a status line from the user's per-currency net in raw pair balances: "you're owed {amounts}" or "you owe {amounts}" joined with " + " when every currency points the same way, "net +{a} -{b}" when they're mixed, "all settled" when there are live records but nothing owed, "no expenses yet" when there's nothing, and "settled · {Mon yyyy}" for a completed trip, with the month in the phone's time zone. `mobile/src/domain/trip-presenter.ts` (`tripCard`)
- With no trips it shows "No trips yet", "Start a trip for a holiday, a flat, or anything you split costs on. Everyone you add sees the same balances." and a "Start a trip" button. `mobile/src/app/(app)/(tabs)/index.tsx`
- Swiping a card left shows "Delete" (light haptic as it opens). Tapping it asks "Delete trip?" with `"{name}" will be removed for everyone.`, "Cancel" and "Delete". Delete gives a success haptic and soft-deletes the trip locally. There's no undo. `mobile/src/app/(app)/(tabs)/index.tsx` (`confirmDelete`), `mobile/src/ui/swipe-row.tsx`
- The floating "Add expense" button opens New expense. `mobile/src/app/(app)/(tabs)/index.tsx`

### New trip

- A modal titled "New trip" with "Cancel" and "Create". Create is enabled when the trimmed name isn't blank and nothing is saving. `mobile/src/app/(app)/new-trip.tsx`
- "Trip name" has the placeholder "Lisbon weekend", takes focus, stops at 100 characters and submits on the keyboard's done key. Under it: "Only people you add can see the trip. They'll see it when they sign in with that email." `mobile/src/app/(app)/new-trip.tsx`
- A "People" section holds the people picker. "Import a group from Splitwise" opens the import modal. `mobile/src/app/(app)/new-trip.tsx`
- Create saves the trip and the user's own joined person row locally in one commit, then adds the picked people. It works offline. The own row uses the account email, or `<user id>@users.tab` when the account has none. Then a success haptic, the modal closes and the new trip opens. A failed save shows "Couldn't create the trip" and leaves the form open. `mobile/src/data/actions.ts` (`createTrip`, `addPeople`)

### People picker

- One search field, "Search names or type an email". Without a query it lists up to 8 people you've split with, and up to 12 matches with one. Matches are by name or email substring. `mobile/src/features/people/people-picker.tsx`
- "People you've split with" means people in trips where you're joined and not removed, excluding removed people, yourself and placeholder `@users.tab` emails. Each email appears once with its newest name, sorted by name. This runs on the local store, so it works offline. `mobile/src/data/selectors.ts` (`knownPeople`)
- A valid typed email that isn't yours, isn't picked and isn't a known person shows an "Add {email}" row. Its name is made from the email, so `jo.bloggs@example.com` becomes "Jo Bloggs". The keyboard's done key adds it too. `mobile/src/features/people/people-picker.tsx`, `mobile/src/features/people/email.ts`
- An email is valid when, trimmed and lowercased, it has no "|", something before the first "@", and a domain after it that contains a dot and doesn't end with one. `mobile/src/domain/presentation-helpers.ts` (`isValidEmail`)
- "Choose from contacts" opens the system contact picker. A contact with no email shows "No email address". A contact with several asks "Which email?" and offers up to four. Picking yourself or someone already picked does nothing. The app never asks for access to the whole address book. `mobile/src/features/people/contacts.ts`
- Picked people show under "Adding {n}" with a remove button. `mobile/src/features/people/people-picker.tsx`

### Trip detail

- The header shows the active members' avatars (up to four) with a "+" that opens People, and a "…" menu. Non-group containers have no "+". `mobile/src/app/(app)/trip/[id].tsx`
- The large title is the trip name. For a non-group container it's the other members' names joined by ", ". `mobile/src/app/(app)/trip/[id].tsx`
- A missing or deleted trip, or one where the user has no person row, shows "Trip not found", "It may have been deleted, or you were removed from it." and "Back". `mobile/src/app/(app)/trip/[id].tsx`
- Under the sync banner come balance cards: one per currency where the user's simplified debts don't net to zero. Each says "You're owed" or "You owe", the amount, and a line per counterparty ("{name} owes you" or "You owe {name}") sorted by amount, then name, then id. With live expenses and nothing owed it shows "All settled" and "Nobody owes anything right now." `mobile/src/domain/balance-presenter.ts` (`balanceSummaries`), `mobile/src/features/ledger/components.tsx` (`BalanceCard`)
- Segments "Expenses", "Balances" and "Overview"; Expenses is the default. The floating "Add expense" button opens the expense form for this trip. Pull to refresh runs a full sync. `mobile/src/app/(app)/trip/[id].tsx`
- Expenses shows the timeline, or "No expenses yet" and "Tap Add expense to log the first one." An expense not yet synced shows "not synced yet" under its amount. `mobile/src/app/(app)/trip/[id].tsx`
- Balances lists everyone's simplified debts, one card per currency in code order, with a currency heading only when there's more than one. Rows read "{from} owes {to}", "You owe {to}" or "{from} owes you", with the amount and "Settle up". Tapping one opens Record a payment filled with that exact debt. Below: "Tap a balance to record a payment. Balances are simplified so the group needs as few payments as possible." With no debts: "Everyone's settled" and "Balances appear here once there are expenses." `mobile/src/domain/balance-presenter.ts` (`simplifiedGroups`), `mobile/src/features/ledger/components.tsx` (`DebtGroups`)
- Overview is described in [Overview segment](#overview-segment).
- The menu, for real trips: "Edit trip", "People", "Record a payment", "Mute notifications" or "Unmute notifications", "Share invite link", "Turn off invite link", "Export spreadsheet". For non-group containers: "Record a payment", the mute item and "Export spreadsheet". `mobile/src/app/(app)/trip/[id].tsx` (`menu`)
- Mute and unmute give a light haptic and save locally; they sync later. `mobile/src/data/actions.ts` (`setTripMuted`)
- "Share invite link" first makes sure the trip is on the server (running a sync if needed), then opens the share sheet with `Join "{trip}" on tab-it: https://tab-it.app/join/<token>`. A failure shows "Invite link unavailable" and the reason, or "You're offline. Connect to the internet and try again." `mobile/src/app/(app)/trip/[id].tsx` (`shareInvite`), `mobile/src/data/online.ts` (`tripInviteUrl`)
- "Turn off invite link" asks "Turn off invite link?" with "People with the old link won't be able to join. Sharing again creates a new link.", "Cancel" and "Turn off". A failure shows "Couldn't turn off the link". `mobile/src/app/(app)/trip/[id].tsx` (`confirmRevoke`)
- "Export spreadsheet" builds the workbook and opens the share sheet (see [Trip export](#trip-export)). A failure shows "Couldn't export". `mobile/src/features/trip/export.ts`
- While the screen is open it listens for live changes to this trip (see [Realtime and polling](#realtime-and-polling)). `mobile/src/data/realtime.ts` (`useTripRealtime`)

### Timeline

- Expenses group by their calendar day; payments group by their local day. Days run newest first. Inside a day, newest created first. The day label is "MMM d" in capitals. `mobile/src/domain/timeline-presenter.ts` (`timelineDays`)
- Each day shows a line per currency, in code order: "{total} · your share {share}". It counts expenses only, never payments. `mobile/src/domain/timeline-presenter.ts`, `mobile/src/features/ledger/components.tsx` (`TimelineRow`)
- Back-to-back expenses share a card; each payment gets its own card. Only the rows near the screen are mounted. `mobile/src/features/ledger/components.tsx` (`timelineEntries`), `mobile/src/app/(app)/trip/[id].tsx`
- An expense row shows the category icon, the description, "Paid by {payer} · {total}" and, on the right, what the user lent or borrowed on it, captioned "you lent" or "you borrowed". When the user's paid and owed match, it shows their share captioned "your share". The payer is "you", a name, "{n} people" for several payers, or a dash when there are none. `mobile/src/domain/timeline-presenter.ts` (`expenseRow`), `mobile/src/features/ledger/components.tsx` (`ExpenseRow`)
- A payment row reads "{from} settled with {to}" (the user is "You" or "you") with the amount. `mobile/src/domain/timeline-presenter.ts` (`settlementRow`)
- Tapping a row gives a light haptic and opens its detail. Rows have no swipe actions; deleting is in the detail menu. `mobile/src/features/ledger/components.tsx`

### Overview segment

- Spend for one currency at a time. With more than one currency, chips pick which. The choice is kept by currency code; if that currency disappears, the first code alphabetically shows. Payments never count. `mobile/src/features/ledger/overview.tsx` (`OverviewSection`), `mobile/src/domain/trip-analytics.ts` (`summarizeSpend`)
- A donut with "TOTAL" and the total spend, filled to the user's share. Beside it "You paid" and "Your share" with "{n}% of trip spend". The donut's accessibility label is "Total spend {total}, your share is {n}% of trip spend". `mobile/src/features/ledger/overview.tsx` (`Summary`), `mobile/src/domain/overview-presenter.ts`
- "Per person · share and paid": each person's share, "paid {amount}" and a bar of share over total. Sorted by share, largest first, then person id descending. `mobile/src/domain/trip-analytics.ts`, `mobile/src/features/ledger/overview.tsx`
- "By category": icon, name ("Other" when unknown), amount, rounded percent of total, and a bar scaled to the largest category. Sorted by total, then category id, with uncategorised last. `mobile/src/domain/trip-analytics.ts`, `mobile/src/app/(app)/trip/[id].tsx` (`buildOverview`)
- With no expenses: "Nothing spent yet" and "The overview fills in as you add expenses." `mobile/src/features/ledger/overview.tsx`

### Edit trip

- A modal titled "Edit trip" with "Cancel" and "Save". Save is enabled when the trimmed name isn't blank and differs from the current one. The name stops at 100 characters. `mobile/src/app/(app)/trip-edit.tsx`
- "Delete trip" asks "Delete trip?" with `"{name}" and its expenses will be removed for everyone in it.`, "Cancel" and "Delete trip". Confirming soft-deletes the trip, gives a success haptic and closes every modal. The note under the button reads "Deleting removes the trip for everyone. Balances in it stop counting towards your friends' totals." `mobile/src/app/(app)/trip-edit.tsx`

### People

- A modal titled "People in {trip}" with "Done". It's reachable only from real trips. `mobile/src/app/(app)/trip-people.tsx`
- A "{n} people" section lists active people in the shared order. The user's row reads "{name} (you)" and can't be tapped. Each row shows the email, or "No email yet" for a placeholder. The badge is empty for joined people, "Not synced yet" for someone added on this phone and not yet sent, "No email" for a placeholder, and "Pending" otherwise. `mobile/src/app/(app)/trip-people.tsx`
- Tapping someone opens an action sheet with their name and email. People who haven't joined get "Add their email" (placeholder) or "Change email". Everyone gets "Remove from trip" and "Cancel". `mobile/src/app/(app)/trip-people.tsx` (`personActions`)
- Remove asks "Remove {name}?" with "Their expenses and balances stay in the trip. You can add them back later with the same email." Someone added on this phone, never sent, and named by no expense or payment is just dropped. Otherwise the server removes them, which needs a connection; a failure shows "Couldn't remove". `mobile/src/data/online.ts` (`removeTripPerson`)
- Under the list: "Pending people join when they open tab-it signed in with that email. Tap someone to add or change their email, or to remove them." Then "Share invite link" for real trips. `mobile/src/app/(app)/trip-people.tsx`
- "Add people" holds the people picker, hiding everyone already in the trip. The button reads "Add {name}" or "Add {n} people". Adding saves locally and works offline. Re-adding a removed person's email restores that same person. `mobile/src/data/actions.ts` (`addPeople`)
- The email sheet is titled "{name}'s email" with "Pick a friend or type their email. They join when they open tab-it signed in with it." It suggests up to four people you've split with who match what's typed, closest name first. An email someone else in the trip already has shows "Someone in this trip already has that email." and can't be saved. "Save email" is enabled for a valid, changed, free email. Saving calls the server, which needs a connection; success gives a success haptic and closes, failure shows the reason with an error haptic. `mobile/src/features/people/email-sheet.tsx`, `mobile/src/data/online.ts` (`updateTripPersonEmail`)
- Giving a placeholder person a real email is how imported Splitwise people get linked to a friend later: the friend claims that spot on their next full sync. `mobile/src/features/people/email-sheet.tsx`

### New expense

- A modal titled "New expense" with "Cancel" and "Next". Next is enabled once a trip or at least one person is picked, and shows a spinner while it works. `mobile/src/app/(app)/new-expense.tsx`
- "Group" opens a menu titled "File this expense under" with "No group" and live trips, newest activity first. `mobile/src/app/(app)/new-expense.tsx`
- With a trip picked it says "Everyone in {trip} will be included. You can change who's in the split next." Next replaces this screen with the expense form for that trip. `mobile/src/app/(app)/new-expense.tsx`
- With "No group" it says "Split something with friends without starting a trip. Only the people you pick will see it." and shows the people picker. Next reuses a non-group container on this phone for exactly these people when one exists. Otherwise it asks the server for one, which needs a connection; errors show under the picker. See [Non-group expenses](#non-group-expenses). `mobile/src/app/(app)/new-expense.tsx` (`proceed`)

### Expense form

- Titled "New expense" or "Edit expense", with "Cancel" and "Save". Cancel discards the draft without asking. `mobile/src/app/(app)/expense-form.tsx`
- If the trip is gone, the user has no person row in it, or the expense being edited is missing or deleted, it shows "This trip isn't available any more." or "This expense isn't available any more." with "Close". `mobile/src/app/(app)/expense-form.tsx`
- The amount field shows the currency symbol, takes focus for a new expense, and shows zero at the currency's precision as its placeholder. Input rules are in [Money and splitting rules](#money-and-splitting-rules). Beside it, a currency pill opens the currency picker. `mobile/src/features/forms/amount-input.tsx`
- Changing currency re-renders the amount and every typed exact payer and split amount at the new precision, and remembers the currency. `mobile/src/app/(app)/expense-form.tsx` (`CurrencyPicker` `onPick`)
- "What was it for?" takes up to 200 characters. `mobile/src/app/(app)/expense-form.tsx`
- Category chips list the six built-ins, then the trip's custom categories. A new expense starts on Food & Drink. `mobile/src/app/(app)/expense-form.tsx` (`categories`)
- The people offered are the trip's active members plus any removed person already on this expense. `mobile/src/app/(app)/expense-form.tsx` (`members`)
- "Paid by" shows a chip per person. The user pays by default. At least one payer stays selected. With two or more payers it shows "Split equally" and "Exact amounts", a row per payer, and a footer: "Each pays {amount}" or "Equal total {total}" when equal, or the exact-amount footer. Tapping an equal payer's amount switches to exact. Switching to exact fills equal amounts. Adding or removing a payer keeps typed amounts, except that one remaining payer gets the whole total. `mobile/src/app/(app)/expense-form.tsx`, `mobile/src/domain/payment-split-draft.ts` (`togglePayer`, `setPayerMode`)
- "Split" shows "{selected} of {people}" and the modes "Equal", "Exact", "Shares" and "Percent". A new expense includes every active member. At least one participant stays selected. Equal shows each computed amount; tapping one switches to Exact and fills equal amounts. Exact shows an amount field per person. Shares and Percent show a weight field ("×" or "%") with the computed amount; shares start at 1 and percentages start equal. Switching modes fills only empty fields. `mobile/src/domain/payment-split-draft.ts` (`setSplitMode`, `toggleParticipant`)
- Footers: exact amounts show "Exact total {total}", "Remaining {amount}" or "Over by {amount}". Shares show "{n} shares total" or "Every participant needs a share". Percentages show "Total 100%", "{n}% left" or "Over by {n}%". Anything that doesn't add up is drawn in the warning colour. `mobile/src/app/(app)/expense-form.tsx` (`reconcile`, `splitFooter`)
- "Details" has "Date" (a calendar day, today by default) and "Paid via": "Cash", "Card" (default) or "Bank transfer", stored as `cash`, `card` and `bank_transfer`. `mobile/src/app/(app)/expense-form.tsx`, `mobile/src/features/forms/date-field.tsx`
- "Receipt", for the person who created the expense (or anyone, for a new one): with no photo, "Take photo" and "Choose photo"; with one, a thumbnail, "New photo" or "Receipt attached", "Replace" (which asks "Take photo" or "Choose from library") and a remove button. Taking a photo asks for camera access; refused access shows "Camera access is off" and "Allow camera access in Settings to photograph receipts." Everyone else sees "Receipt attached" or "No receipt" and "Only the person who added this expense can change its receipt." `mobile/src/app/(app)/expense-form.tsx` (`pickReceipt`)
- Save checks, in order: the amount ("Enter the amount." or "Enter a valid amount."; it must be positive and fit the currency's precision), the description ("Add a description."), the payers ("What people paid must add up to the total. {footer}." or "Check who paid.") and the split ("The split doesn't add up. {footer}." or "Check the split amounts."). With a problem, Save shows the messages inline, gives a warning haptic and an alert "Can't save yet" with the first one. `mobile/src/app/(app)/expense-form.tsx` (`problems`, `save`)
- Saving prepares any new photo first, then writes the expense and replaces both ledgers in one local commit. An edit keeps the id, creator and creation time and sets the editor to the user. The description is trimmed and cut to 200 characters. Then it remembers the currency, gives a success haptic and closes. It works offline. A failure shows "Couldn't save the expense" and keeps the form. `mobile/src/data/actions.ts` (`saveExpense`)
- Editing fills the form once from the saved expense: amount, currency, description, category, date, method, payers and their mode, the split mode (from the first split row), participants and each person's amount, shares or percentage. `mobile/src/app/(app)/expense-form.tsx` (`seed`)

### Expense detail

- A missing or deleted expense shows "Expense not found", "It may have been deleted." and "Back". `mobile/src/app/(app)/expense/[id].tsx`
- The top shows the category icon and name ("Other" when unknown) in the category's tint, then the description. A refused change shows its reason with "Review"; an unsynced one shows "Saved on this phone. It will sync when you're online." `mobile/src/app/(app)/expense/[id].tsx`
- A card shows "TOTAL", the amount, the day of the month and "mon yyyy" in lower case. `mobile/src/app/(app)/expense/[id].tsx`
- "Paid by" reads "You paid the bill" when the user is the only payer, else one row per payer. "Split" lists each participant, with a footer "{split type} · {n} ways". Rows put the user first, then names. `mobile/src/app/(app)/expense/[id].tsx`
- "Details" shows "Date" ("9 June 2026"), "Paid via", "Logged by", "Logged at" ("9 Jun 2026, 09:52" in local time) and, once someone has edited it, "Edited by" and "Edited at". Names are "You", the person's name, the profile name, or "Member". `mobile/src/app/(app)/expense/[id].tsx`, `mobile/src/lib/dates.ts`
- "Receipt" shows the photo from this phone's waiting copy, or else from a signed URL, with a spinner while loading. Waiting photos say "Uploading when you're online." A refused upload says "The photo couldn't be uploaded. Edit the expense and attach it again." to the creator and "Only the person who added this expense can upload its receipt." to others. A load failure shows "Couldn't load the receipt. Tap to try again." Tapping the photo opens it full screen on black with a close button. `mobile/src/app/(app)/expense/[id].tsx` (`Receipt`)
- The menu has "Edit expense" and "Delete expense". Delete asks "Delete this expense?" with "It will be removed from balances for everyone." Confirming soft-deletes it, gives a success haptic and goes back. `mobile/src/app/(app)/expense/[id].tsx`, `mobile/src/data/actions.ts` (`deleteExpense`)

### Record a payment

- Titled "Record a payment" or "Edit payment", with "Cancel" and "Save". It records money that moved outside the app: "This records money that changed hands outside the app. It doesn't send a payment." `mobile/src/app/(app)/settle-up.tsx`
- A missing trip, no own person row, or a missing or deleted payment being edited shows "This trip isn't available any more." or "This payment isn't available any more." with "Close". `mobile/src/app/(app)/settle-up.tsx`
- It starts from, in order: the payment being edited; a debt passed in from trip Balances or a friend's source; the user's suggested payment; or the user paying the first other active member with an empty amount in the trip's default currency. `mobile/src/app/(app)/settle-up.tsx` (`initial`)
- The suggested payment is the user's largest simplified debt, or if they owe nothing, the largest one owed to them. Ties go to the currency code, then the other person's id. `mobile/src/domain/balance-presenter.ts` (`suggestedPayment`)
- "From" and "To" are menus. Each leaves out the person picked in the other. They offer active members plus any removed person who's selected or in a current debt. `mobile/src/app/(app)/settle-up.tsx` (`people`)
- Debts are worked out without the payment being edited, so its own amount doesn't count twice. `mobile/src/app/(app)/settle-up.tsx` (`debts`)
- On a new payment the user hasn't typed into, changing From, To or the currency fills the amount with the open debt between that pair, or clears it. Once they've typed, it's left alone. `mobile/src/app/(app)/settle-up.tsx` (`prefill`)
- When the pair has an open debt in this currency, a note reads "{from} owes {to} {owed}." followed by " After this, {rest} will remain.", " This settles the full balance." or " This overpays by {extra}." When the debt runs the other way: "{to} owes {from} {owed}. This payment goes the opposite way." With "You" the verb is "owe". No debt means no note. `mobile/src/app/(app)/settle-up.tsx` (`context`)
- Errors, shown once an amount is typed: "Choose who paid and who received it.", "Pick two different people." and "Enter an amount greater than zero." `mobile/src/app/(app)/settle-up.tsx` (`errors`)
- "Details" has "Date" and "Add a note (optional)", up to 200 characters. `mobile/src/app/(app)/settle-up.tsx`
- The saved time keeps the old time when the day hasn't changed, uses now when the day is today, and uses local noon otherwise. `mobile/src/app/(app)/settle-up.tsx` (`settledAtFor`)
- Saving writes locally (works offline), keeps the creator and creation time on edits, trims a blank note to none, remembers the currency, gives a success haptic and closes. A failure shows "Couldn't save". `mobile/src/data/actions.ts` (`saveSettlement`)

### Payment detail

- A missing or deleted payment shows "Payment not found", "It may have been deleted." and "Back". `mobile/src/app/(app)/settlement/[id].tsx`
- It shows the same refused or unsynced banner as an expense, then "PAYMENT", the amount, and both people's avatars with an arrow. "Details" has "Date", "Note" when there is one, "Recorded by" and "Recorded at". `mobile/src/app/(app)/settlement/[id].tsx`
- The menu has "Edit payment" and "Delete payment". Delete asks "Delete this payment?" with "It will be removed from balances for everyone." `mobile/src/app/(app)/settlement/[id].tsx`

### Friends tab

- The title is "Friends". Pull to refresh runs a full sync. The floating "Add expense" opens New expense. `mobile/src/app/(app)/(tabs)/friends.tsx`
- Friends come from every live container the user is in, trips and non-group ones alike: everyone active in them, plus anyone the user still has a balance with. A person is their account when joined, or their email when pending. A pending email that belongs to a joined person anywhere counts as that person, so they appear once. `mobile/src/domain/friends-presenter.ts` (`friendsContext`, `friendsList`)
- Balances net each trip's simplified debts across trips, per currency. They never mix currencies. `mobile/src/domain/friends-presenter.ts`, `mobile/src/domain/overall-balance-aggregator.ts` (`aggregateBalances`)
- An "OVERALL" card has a line per currency with the gross totals: "You owe {amount}" and "you're owed {amount}", separated by a dot when both apply. `mobile/src/app/(app)/(tabs)/friends.tsx`
- "People" lists friends with a balance and "Settled up" those without, each sorted by name. A row shows the avatar, name, a subtitle ("Invite pending" for a pending person, "all settled", or where you share costs: "Non-group", a trip name, "{n} trips", or "Non-group + …"), and "OWES YOU" or "YOU OWE" amounts per currency. `mobile/src/app/(app)/(tabs)/friends.tsx`, `mobile/src/domain/friends-presenter.ts` (`sourceSummary`)
- With nobody: "No friends yet", "Add an expense or start a trip to see who owes who." and "Add an expense". `mobile/src/app/(app)/(tabs)/friends.tsx`

### Friend detail

- An unknown friend shows "Nothing shared yet" and "Back". `mobile/src/app/(app)/friend/[key].tsx`
- The top shows the avatar, name, "Invite pending" when pending, and a line per currency: "{name} owes you {amount}" or "You owe {name} {amount}", or "All settled up". `mobile/src/app/(app)/friend/[key].tsx`
- "Balance by source" lists each container and currency with a non-zero balance, sorted by container id then currency. Each row shows an icon (people for non-group, a plane for a trip), the source name ("Non-group" or the trip name), and the amount labelled "OWES YOU" or "YOU OWE". Tapping one gives a light haptic and opens Record a payment for that container, filled with that direction and amount. Below: "Tap a source to settle up there." With none: "You're all settled up." A friend can be all settled overall and still have sources that cancel out. `mobile/src/domain/friends-presenter.ts` (`friendDetail`)
- "Shared history" holds every live expense where both people pay or take part, and every payment directly between them. Days run newest first, newest created first within a day. Rows show the category icon and the source name, and open the detail. `mobile/src/domain/friends-presenter.ts` (`friendDetail`), `mobile/src/features/ledger/components.tsx` (`ExpenseRow`, `SettlementRow`)

### Activity tab

- The title is "Activity". Opening the tab pulls unless a full pull finished in the last 30 seconds, and pull to refresh runs a full sync. `mobile/src/app/(app)/(tabs)/activity.tsx`
- It shows every activity row on this phone, newest first, except rows hidden here. That includes the user's own actions and muted trips. Sections are "Today", "Yesterday", "Wednesday, Jun 3" this year, or "Jun 3, 2025" for other years. `mobile/src/domain/activity-presenter.ts` (`activitySections`)
- A row shows an icon, the title, "{trip}" with "{from} → {to}" for payments, the amount when the event has one, and the time ("9:52 AM"). Deletes and removals use the warning tint and strike through the amount. Unread rows have a dot and a tinted background. `mobile/src/app/(app)/(tabs)/activity.tsx` (`ActivityItem`)
- Titles: "{actor} added {description}", "{actor} edited {description}", "{actor} deleted {description}", "{actor} recorded a payment", "{actor} edited a payment", "{actor} removed a payment", "You were added to {trip}" when the new member is the user or else "{actor} added {member}", "{actor} removed {member}", "{actor} created {trip}", "{actor} renamed the trip to {trip}", and "{actor} updated {trip}" for anything else. Missing names fall back to "Someone", "a trip", "an expense" and "someone". `mobile/src/domain/activity-presenter.ts` (`activityRow`)
- A row is unread when someone else did it, the trip isn't muted, it hasn't been read or hidden on this phone, it's newer than the read cursor, and it isn't older than the moment the user joined that trip. `mobile/src/domain/activity-presenter.ts` (`isActivityUnread`)
- Tapping marks the row read here, gives a light haptic and opens the expense or payment if it still exists, or else the trip. `mobile/src/app/(app)/(tabs)/activity.tsx` (`open`), `mobile/src/domain/activity-presenter.ts` (`activityNavigation`)
- Swiping right on an unread row shows "Read". Swiping left shows "Hide", which marks it read and hides it on this phone only. Both are also accessibility actions. Nothing is deleted on the server. `mobile/src/app/(app)/(tabs)/activity.tsx`, `mobile/src/data/actions.ts` (`markActivityRead`)
- Leaving the tab with any unread rows moves the read cursor to now, which clears the badge on every device once synced. Dots stay while the user is reading. `mobile/src/app/(app)/(tabs)/activity.tsx`, `mobile/src/data/actions.ts` (`markActivitySeen`)
- With nothing: "No activity yet" and "Updates from your trips show up here." `mobile/src/app/(app)/(tabs)/activity.tsx`

### Settings tab

- The name row shows the profile name and the email, or "Email hidden by Apple" for an Apple private relay address. "Edit" turns it into a field (up to 60 characters) with "Save". The new name shows on the user's trip rows at once and syncs later. Under it: "Friends see this name on trips you share." `mobile/src/app/(app)/(tabs)/settings.tsx`, `mobile/src/data/actions.ts` (`updateDisplayName`)
- "Sync" shows "Status": "Syncing…", "Offline", "Offline · {n} waiting", "{n} couldn't be saved", "{n} waiting" or "Up to date · {when}". Then "Sync now", and "Review unsynced changes" when anything is waiting or refused. `mobile/src/app/(app)/(tabs)/settings.tsx` (`syncLabel`)
- "Notifications" shows "Push notifications" with "On", "Off. Turn them on in Settings." (and "Open Settings"), "Not set up yet" (and "Turn on", which shows the system prompt), "Not available on this device", or on Android "Coming to Android later. Activity shows every update meanwhile." It rechecks whenever the tab opens. `mobile/src/app/(app)/(tabs)/settings.tsx` (`pushLabel`)
- "Preferences" has "Default currency", showing the saved code or "Automatic", which opens the currency picker. Under it: "New expenses use the trip's latest currency. This is the fallback for new trips." `mobile/src/app/(app)/(tabs)/settings.tsx`, `mobile/src/features/currency/defaults.ts`
- "Trips" has "Join a trip with an invite link" and "Import from Splitwise". `mobile/src/app/(app)/(tabs)/settings.tsx`
- "About" has "Privacy policy" (in-app browser), "Contact support" (`mailto:support@tab-it.app`) and "Version" as "{version} ({build})". `mobile/src/app/(app)/(tabs)/settings.tsx`
- "Sign out" with nothing unsynced asks "Sign out?" with "Your trips stay on the server. Sign back in any time to see them." With unsynced changes it asks "You have unsynced changes" with "{n} changes haven't reached the server yet. Signing out now deletes them from this phone." and offers "Cancel", "Sync first" and "Sign out anyway". "Sync first" syncs and signs out only if nothing is left; otherwise "Still not synced" and "Connect to the internet, then try again. Nothing was signed out." The count is the [unsynced changes list](#unsynced-changes). `mobile/src/app/(app)/(tabs)/settings.tsx` (`confirmSignOut`)
- Signing out first removes this phone's push token from the server. If that can't be done, the app asks "You're offline" with "Cancel" and "Sign out anyway", because the phone may keep showing that account's notifications until someone signs in on it. `mobile/src/app/(app)/(tabs)/settings.tsx` (`doSignOut`), `mobile/src/data/push.ts` (`unregisterPushDevice`)
- "Delete account" asks "Delete your account?" with "This permanently deletes your account. Trips only you joined are erased, including their expenses. In shared trips, expenses stay visible to other members, but your email and profile are removed. This cannot be undone." Both buttons are disabled while either runs. A failure shows "Couldn't delete account" and "Couldn't delete your account. Check your connection and try again." `mobile/src/app/(app)/(tabs)/settings.tsx` (`confirmDelete`), `mobile/src/data/auth.ts` (`deleteAccount`)

### Join a trip with an invite link

- A dialog titled "Join a trip" with "Paste the invite link someone sent you.", a field, "Cancel" and "Join". `mobile/src/features/settings/join-by-link.tsx`
- It accepts `http(s)://tab-it.app/join/<token>`, the same with `www.`, `com.rithwikshetty.tab://join/<token>`, or the bare 32-character hex token. Anything else shows "That doesn't look like a tab-it invite link." `mobile/src/domain/auth-helpers.ts` (`inviteToken`), `mobile/src/data/invites.ts` (`isInviteToken`)
- Joining needs a connection. Success gives a success haptic, closes and opens the trip. Failure gives an error haptic and the invite error message. `mobile/src/features/settings/join-by-link.tsx`, `mobile/src/data/online.ts` (`inviteErrorMessage`)

### Import from Splitwise

- Reached from New trip and from Settings. The first screen reads "Bring a Splitwise group into tab-it", "In Splitwise, open a group, choose Export as spreadsheet, and save the CSV. Then pick it here." and "Choose CSV file". `mobile/src/app/(app)/import-splitwise.tsx`
- Files over 5 MB are refused with "Couldn't read that file. It's larger than 5 MB." Parse errors show "That file is empty.", "No people were found in that export." or "That doesn't look like a Splitwise export. Use the spreadsheet (CSV) export from a group." `mobile/src/app/(app)/import-splitwise.tsx` (`choose`, `parseError`)
- The review shows "Trip name" (the file name without its extension, or "Imported trip"; up to 100 characters), then "Which one is you?" with every name and "I'm not in this group". The name closest to the user's name is picked to start: an exact match, case and outer spaces aside, else the most shared words. Picking a name as "you" drops any email linked to it. `mobile/src/app/(app)/import-splitwise.tsx`, `mobile/src/domain/splitwise-importer.ts` (`bestSelfMatch`)
- "Who's everyone else?" lists the other names with the email each will be added under, or "No email yet". A name starts linked only when exactly one person you've split with has exactly that name, and each email is used once. Tapping a row opens the email sheet, with "Remove email" to take it off. `mobile/src/domain/splitwise-importer.ts` (`suggestImportLinks`), `mobile/src/app/(app)/import-splitwise.tsx`
- A summary reads "{n} people · {n} expenses · {n} payments" and "People with an email join when they open tab-it signed in with it. Anyone without one is added by name, and you can add their email later from the trip's People screen." `mobile/src/app/(app)/import-splitwise.tsx`
- "Notes ({n})" lists up to 50 parser warnings as "Line {n}: {message}". `mobile/src/app/(app)/import-splitwise.tsx`
- "Import {name}" (or "Import trip") is disabled while the name is blank. "Choose another file" starts over. Cancel is disabled while importing. `mobile/src/app/(app)/import-splitwise.tsx`
- Importing creates the trip, the people, every expense with both ledgers, and every payment in one local commit, so it works offline and syncs like any other change. Then a success haptic, every modal closes and the trip opens. A failure shows "Couldn't import". See [Splitwise import rules](#splitwise-import-rules). `mobile/src/data/actions.ts` (`importSplitwise`)

### Unsynced changes

- A modal titled "Unsynced changes" with "Done", opened from the sync banner, Settings and the detail banners. `mobile/src/app/(app)/sync-issues.tsx`
- With nothing waiting: "Everything is synced" and "All your changes are saved on the server." `mobile/src/app/(app)/sync-issues.tsx`
- "Couldn't be saved" lists refused changes with their reason and a "Discard" button, then "The server refused these. Usually the trip was deleted or you were removed from it. Discard them, or fix and save again." `mobile/src/app/(app)/sync-issues.tsx`
- "Waiting to sync" lists the rest, then "These will sync when you're back online." when offline or "These are on their way." `mobile/src/app/(app)/sync-issues.tsx`
- The list has: real trips not yet acknowledged ("New trip", "Trip changes" or "Delete trip"); people who haven't joined, added or changed here ("Person in {trip}"); expenses ("Expense in {trip}" or "Delete expense in {trip}"); payments ("Payment in {trip}" or "Delete payment in {trip}"); receipt photos still waiting, or refused, on an expense that's otherwise synced ("Receipt photo in {trip}"); a renamed profile ("Your name"); and mute changes ("Mute notifications" or "Unmute notifications"). Non-group containers are named "Non-group". `mobile/src/data/selectors.ts` (`unsyncedChanges`)
- Tapping an expense or receipt row opens the expense; other rows open the trip. `mobile/src/app/(app)/sync-issues.tsx`
- "Discard" asks "Discard this change?" with "It will be removed from this phone. The server's version stays as it is." A row that never reached the server is deleted with its children. A receipt loses its waiting photo. Anything else is marked acknowledged, so the next pull brings back the server's copy or removes it. Then a full sync runs. `mobile/src/data/actions.ts` (`discardLocalChange`)
- "Try again now" runs a full sync. `mobile/src/app/(app)/sync-issues.tsx`

## Cross-cutting behaviour

### Local store and offline-first writes

- Every screen reads the local store. Each signed-in user has their own SQLite file, `tab-<user id>.db`, holding rows as JSON keyed by table and server primary key, plus a key-value meta table. All rows also live in memory. `mobile/src/data/store.ts`
- A commit changes memory at once, tells subscribers, then writes one SQLite transaction, in commit order. If a write fails, memory reloads from disk and every commit queued behind it fails too, so nothing syncs on top of a change the phone never stored. If the reload fails, writes are refused with "This phone's storage isn't working. Restart the app." `mobile/src/data/store.ts` (`commit`)
- Rows keep Supabase column names. Local bookkeeping uses underscore fields: `_pushed` (the write_id the server last acknowledged, or null if never sent), `_error` (why the server refused it), `_receipt` and `_receiptFile` (a photo waiting to upload), `_deleted` (an unmute waiting to be sent), and `_readAt` / `_dismissedAt` (activity read or hidden here). A row is dirty while `_pushed` differs from `write_id`. `mobile/src/data/schema.ts`
- Every local edit gets a fresh `updated_at` and `write_id`. Deletes set `deleted_at` (soft delete) on trips, expenses and payments. `mobile/src/data/actions.ts` (`stamp`, `deleteTrip`, `deleteExpense`, `deleteSettlement`)
- Only server-owned operations need a connection: changing a person's email, removing a person who reached the server, invite links, joining by invite, finding a non-group container, and deleting the account. `mobile/src/data/online.ts`, `mobile/src/data/auth.ts` (`deleteAccount`)

### Sync engine

- One engine per signed-in session keeps the store and Supabase in step. Runs never overlap: a trigger during a run is folded into one more pass. Each pass pushes, then pulls everything or just the requested trips. `mobile/src/data/sync.ts` (`SyncEngine.run`)
- Triggers: start-up (full pull); a local change that can be pushed (push after 400 ms); returning to the foreground (full pull); the network coming back after being offline (full pull); every five minutes while the app is active (full pull); pull to refresh, "Sync now" and "Try again now" (full pull, resets the retry wait); a realtime change, a push tap or a joined invite (that trip); a push arriving in the foreground (full pull); opening the Activity tab (full pull, unless one finished in the last 30 seconds). `mobile/src/data/sync.ts` (`start`, `request`, `refresh`), `mobile/src/app/(app)/_layout.tsx`, `mobile/src/data/realtime.ts`
- A network failure or server hiccup stops the run, sets the status to offline ("You're offline. Changes are saved on this phone and will sync when you reconnect.") and retries after 2, 5, 15, 30, then every 60 seconds while the app is active. `mobile/src/data/sync.ts` (`scheduleRetry`), `mobile/src/data/remote.ts` (`toRemoteError`)
- A row the server refuses keeps its reason in `_error`, the run moves on, and the status counts it as failed. Every run tries refused rows again, but a refused row on its own doesn't start a run. `mobile/src/data/sync.ts` (`attempt`, `reject`, `start`)
- Push order: own profile (`ensure_current_profile`), real trips, people, expenses, payments, receipt photos, mutes, the activity read cursor. `mobile/src/data/sync.ts` (`push`)
- A pushed row is acknowledged with the write_id that was sent, applied to the row as it is now. An edit made while the request was in flight stays dirty and goes next time. `mobile/src/data/sync.ts` (`ack`)
- New trips go through `create_trip_with_self` with the trip id, the creator's person id and the name. Later edits update `name`, `deleted_at`, `updated_at` and `write_id` and ask for the row back; if no row comes back, the user isn't allowed to change it and the change is refused with "This was deleted, or you no longer have access to it." A trip deleted before the server acknowledged it still sends the delete, then goes from this phone with everything in it. Non-group containers are never pushed. `mobile/src/data/sync.ts` (`pushTrips`, `pushTrip`, `updateOne`)
- People added here go through `add_trip_person_by_email` with their local id once their trip is on the server. If the server answers with an existing row for that email under another id, the local person is replaced, every payment, split and settlement naming them moves to the server's id, and those rows are marked for another push. Forms still open on the old id are mapped forward. A person removed here while being added is removed on the server too. `mobile/src/data/sync.ts` (`pushPeople`), `mobile/src/data/merge.ts` (`adoptServerPerson`), `mobile/src/data/actions.ts` (`resolvePerson`)
- Expenses and payments wait until their trip and every person they name are on the server. If a named person was refused or discarded, the row is refused with "Someone on this couldn't be added to the trip." `mobile/src/data/sync.ts` (`whenPeopleReady`, `tripReady`)
- An expense goes through `create_expense_with_payments_and_splits` with the expense, its payments and its splits, money as decimal strings. A deleted expense updates only `deleted_at`, `updated_at` and `write_id`. One deleted before it was ever acknowledged sends the delete if the trip is on the server, then goes from this phone with its ledgers. `mobile/src/data/sync.ts` (`pushExpenses`, `pushExpense`)
- A new payment is upserted on `id`, so a retry after a lost response is harmless. An existing payment, even someone else's, is changed with an update. Deletes work like expense deletes. `mobile/src/data/sync.ts` (`pushSettlements`, `pushSettlement`)
- Rows under a deleted trip are cleared by the engine instead of waiting: people waiting to be added are dropped, never-sent expenses and payments are dropped, and sent ones are acknowledged without sending, because the server refuses writes under a deleted trip. `mobile/src/data/sync.ts` (`pushPeople`, `pushExpenses`, `pushSettlements`)
- Muting upserts `{trip_id, user_id, muted_at, updated_at, write_id}`. Unmuting deletes the server row, then removes the local row unless it changed meanwhile. `mobile/src/data/sync.ts` (`pushMutes`)
- The read cursor (`activity.seenAt` in meta) goes up through `mark_activity_seen`. A later cursor from the server replaces the local one. `mobile/src/data/sync.ts` (`pushActivitySeen`, `seenCursorOps`)
- The status counts dirty trips, people, expenses, payments, mutes and profiles, plus waiting and refused receipt photos, as pending, and those with an error, and refused photos, as failed. `mobile/src/data/sync.ts` (`refreshCounts`)

### Pull and conflict rules

- A full pull first calls `claim_trip_people_for_current_email`, so a trip someone added the user to arrives in the same pull. A failed claim doesn't stop the pull. Then every table loads in parallel, along with `activity_read_cursor`. `mobile/src/data/sync.ts` (`pull`)
- A trip pull loads only that trip's row, its people, its expenses with their ledgers, its payments and its activity. It skips categories, mutes and the read cursor. `mobile/src/data/remote.ts` (`fetchSnapshot`)
- Tables load 1000 rows a page, keyed on `id`, so rows added or removed mid-pull can't shift later pages. Mute preferences page by offset. Activity loads the newest 300 rows from the last 90 days. Profiles come from `visible_profiles`. Expenses come with their payment and split rows embedded. `mobile/src/data/remote.ts` (`fetchAllById`, `fetchSnapshot`)
- Money columns are read with `::text`, so no amount ever passes through a JavaScript number. `mobile/src/data/remote.ts` (`EXPENSE_COLUMNS`, `SETTLEMENT_COLUMNS`)
- A table that fails to load counts as unknown: nothing is removed on its account. The error is raised after the rest has merged. `mobile/src/data/remote.ts` (`fetchSnapshot`), `mobile/src/data/sync.ts` (`pull`)
- Merging follows the server's rules. A clean local row always takes the server's version. A dirty one compares with it: the same write_id means the server already has it, so it's acknowledged; otherwise a delete beats a live row, two deletes compare `deleted_at`, two live rows compare `updated_at` to the microsecond, and an exact tie goes to the larger write_id. A dirty row that would win stays and is pushed next. `mobile/src/data/merge.ts` (`resolveConflict`, `mergeRemote`)
- A trip's `last_activity_at` moves forward from the server even while a local rename or delete is waiting. `mobile/src/data/merge.ts` (`mergeRemote`, trips)
- When an expense takes the server's version, its payment and split rows are replaced with the server's. Pulled amounts are rounded to the currency's minor unit, half away from zero. A waiting receipt photo survives as long as the storage path didn't change. `mobile/src/data/merge.ts` (`mergeRemote`, expenses)
- A row that was on the server but is missing from a complete pull was deleted there or is hidden from this account. A clean copy is removed. An unsent edit stays, marked "This was deleted, or you no longer have access to it.", so the user can see and discard it. A trip holding unsent expenses or payments, and a person an unsent row names, stay the same way. A removed trip takes everything in it; a removed expense takes its ledgers. `mobile/src/data/merge.ts` (`vanish`)
- Clean mute rows missing from the server are removed (another device unmuted). Other people's profiles missing from `visible_profiles` are removed. `mobile/src/data/merge.ts`
- Activity only grows: new rows are added and existing ones keep their read and hidden marks. Rows older than 90 days, and rows for trips missing from a full pull, are dropped. `mobile/src/data/merge.ts` (`ACTIVITY_WINDOW_DAYS`)
- Timestamps compare as integer microseconds, matching Postgres. `mobile/src/data/timestamps.ts`

### Realtime and polling

- While a trip that's on the server is on screen, the app subscribes to changes on its `expenses`, `settlements` and `trip_people` (filtered by `trip_id`) and its `trips` row (filtered by `id`). Any event pulls that trip 400 ms later. The subscription pulls once when it connects, and reconnects when the app returns to the foreground. Leaving the screen unsubscribes and cancels a waiting pull. `mobile/src/data/realtime.ts`
- Payment and split rows have no `trip_id`, so they arrive through the expense change and the trip pull. `mobile/src/data/realtime.ts`
- Everything else updates through the five-minute poll and the other full-pull triggers. `mobile/src/data/sync.ts` (`POLL_INTERVAL`)

### Receipts

- Photos live in the private `receipts` bucket at `{trip id}/{expense id}.jpg`. `mobile/src/data/receipts.ts` (`receiptPath`)
- A picked or taken photo becomes a JPEG at most 2048 px on its long edge, quality 0.92, under 9,500,000 bytes. If it's still too big, the edge shrinks by a quarter each try down to 480 px, then fails with "That photo is too large to attach." `mobile/src/data/receipts.ts` (`stageReceipt`)
- The prepared photo waits in `documents/receipts/<user id>/` under a name that includes the expense's write_id, so a newer photo never overwrites one that's uploading. The expense is marked `_receipt: "pending"`. A replaced or removed photo's waiting copy is deleted once the save is stored. `mobile/src/data/receipts.ts`, `mobile/src/data/actions.ts` (`saveExpense`)
- A photo uploads once its expense is synced, as `image/jpeg` with upsert. Success clears the mark and deletes the copy. A refusal, or a missing copy, marks it `"failed"`. A network failure stops the run for a retry. A deleted expense's photo is discarded. Only the photo that was sent is settled; a newer one stays waiting. `mobile/src/data/receipts.ts` (`uploadPendingReceipts`)
- Showing a receipt uses the waiting copy if there is one, else a one-hour signed URL that's reused for 50 minutes. The image cache key includes the expense's write_id, so a replaced photo at the same path isn't served stale. `mobile/src/data/receipts.ts` (`receiptSource`)
- Waiting photos that no expense refers to are deleted when the store opens. `mobile/src/data/receipts.ts` (`pruneStagedReceipts`)
- The app never deletes a photo from the bucket. The server removes a photo once no live expense has pointed at it, and neither the photo nor its expense has changed, for 30 days. `supabase/sql/22_receipt_sweep.sql`, `supabase/functions/sweep-receipts/index.ts`
- Only the expense's creator may write its photo. The form only lets the creator change it. `supabase/sql/01_private_helpers.sql` (`can_write_receipt_object`), `mobile/src/app/(app)/expense-form.tsx` (`isCreator`)

### Push notifications and activity

- Push works on iOS only. The server stores APNs tokens and sends through APNs. Android shows updates in the Activity tab. `mobile/src/data/push.ts` (`PUSH_SUPPORTED`)
- The system prompt waits until the user has a live real trip: at once if they already do, else when the first one arrives. Before that, and on every return to the foreground, the app re-registers silently when permission is already given, so token changes and reinstalls heal themselves. Provisional permission counts as granted. `mobile/src/app/(app)/_layout.tsx` (`usePush`), `mobile/src/data/push.ts` (`registerForPush`)
- Registering sends the APNs device token and device name to `register_push_device` and keeps the token in SecureStore so sign-out can remove it. `mobile/src/data/push.ts`
- Foreground notifications show a banner, go in the list, play a sound and set the badge, and the app pulls. `mobile/src/data/push.ts`, `mobile/src/app/(app)/_layout.tsx`
- Tapping a push, including one that launched the app, pulls that trip, opens it, and then opens the expense or payment if it still exists. Each tap is handled once. `mobile/src/app/(app)/_layout.tsx` (`usePush`), `mobile/src/data/push.ts` (`pushTarget`)
- The app icon badge follows the local unread count. `mobile/src/app/(app)/_layout.tsx`, `mobile/src/data/push.ts` (`setBadgeCount`)
- The server writes one activity row per event from database triggers: `expense_created`, `expense_updated`, `expense_deleted`, `settlement_created`, `settlement_updated`, `settlement_deleted`, `member_joined`, `member_left`, `trip_created` and `trip_updated`. Each carries a snapshot of names, description and amount from the moment it happened. Non-group containers log expense and payment events but not trip or member events. `supabase/sql/09_activity_log.sql`
- The push sender rereads the activity row and sends to trip members other than the actor, skipping muted trips. The title is the trip name (or "tab-it"); the body matches the activity wording, with "{currency} {amount}" on creates and edits. The badge is each recipient's unread count. Pushes group by trip and collapse repeat edits of one record. `supabase/functions/send-push/index.ts`, `supabase/sql/18_notifications_push.sql` (`push_targets_for_activity`)
- Muting silences pushes and the unread count for that trip; its events still show in Activity. `mobile/src/domain/activity-presenter.ts` (`isActivityUnread`), `supabase/sql/18_notifications_push.sql`

### Invites, claims and membership

- A saved invite token is redeemed when the signed-in shell opens, each time the app returns to the foreground, and right after a link is saved. `mobile/src/app/(app)/_layout.tsx` (`usePendingInvite`), `mobile/src/data/invites.ts` (`onPendingInvite`)
- Redeeming calls `join_trip_with_invite` with the token and a new person id, pulls that trip and opens it. A network failure saves the token again for the next try. Any other failure shows "Can't join trip" with the message. `mobile/src/data/online.ts` (`joinTripWithInvite`)
- Invite messages: a network failure gives "You're offline. Connect to the internet and open the invite link again."; error `22023` gives "Your account doesn't have a verified email. Verify your email, then open the invite link again."; `P0002` or `42501` gives "This invite link is invalid or was turned off."; anything else shows the server's message. `mobile/src/data/online.ts` (`inviteErrorMessage`), `mobile/src/domain/presentation-helpers.ts` (`inviteJoinErrorMessage`)
- An invite token is 32 lowercase hex characters. The server keeps one live token per trip and makes a new one after it's turned off. `supabase/sql/21_trip_invites.sql`
- Joining restores the user's own row in that trip if it exists, even a removed one; otherwise it claims a pending row with their email, or adds them. A row belonging to another account never moves. `supabase/sql/21_trip_invites.sql` (`join_trip_with_invite`)
- Claims use the account's email from `auth.users`. They take only unclaimed, not-removed rows, and never a second row in a trip where the user already has one. `supabase/sql/15_rpc_trip_people.sql` (`claim_trip_people_for_current_email`)
- Adding by email normalises the email, restores a removed person with that email, and keeps the name of someone who has already joined. Email changes are only for pending, not-removed people, and an email already in the trip is refused ("Someone in this trip already has that email"). Nobody can remove themselves. Membership never changes by direct table writes. `supabase/sql/15_rpc_trip_people.sql`

### Non-group expenses

- Each distinct set of people has one hidden container of kind `non_group`, with a `member_signature` of the sorted lowercase emails joined by "|". The user's own email is part of it, or `<user id>@users.tab` without one. `mobile/src/app/(app)/new-expense.tsx` (`localContainer`), `supabase/sql/19_rpc_non_group.sql`
- The app reuses a matching container already on the phone. Otherwise `resolve_or_create_non_group_container` returns its people, the app saves them and a placeholder container row that's never pushed, and the next pull replaces it. With no other person it shows "Pick at least one other person." `mobile/src/data/online.ts` (`resolveNonGroupContainer`)
- Non-group containers never show in Trips. They show in Friends as "Non-group", and their detail screen has no rename, people, invite or add-person controls. `mobile/src/data/selectors.ts` (`liveTrips`), `mobile/src/app/(app)/trip/[id].tsx`

### Money and splitting rules

- Rows hold money as decimal strings. Maths uses `bigint` counts of minor units: USD "12.5" is `1250n`, JPY "1250" is `1250n`, KWD "1.250" is `1250n`. Money never passes through a JavaScript `number`. `mobile/src/domain/money.ts` (`toMinor`, `fromMinor`)
- Converting a decimal to minor units rounds half away from zero. Display rounding is half to even. The calculators refuse amounts with more decimals than the currency allows. `mobile/src/domain/money.ts`, `mobile/src/domain/money-formatter.ts`, `mobile/src/domain/split-calculator.ts`
- Amount entry keeps digits, "." and ",". With both marks, the last one is the decimal mark and the other is grouping. Several of only one mark are grouping. A single comma becomes a dot. Typing stops at the currency's decimal digits, at twelve whole digits (the server's `numeric(20,8)` limit), and for a zero-decimal currency at the decimal mark. `mobile/src/domain/money.ts` (`sanitizeAmountInput`)
- Share and percentage entry keeps two decimals, either mark. `mobile/src/domain/money.ts` (`sanitizeShareInput`)
- Equal splits floor the total over the number of people and give the leftover minor units one each to the lexicographically lowest UUIDs. 10.00 over A, B and C is 3.34, 3.33, 3.33 whatever their order. Rows keep the caller's order. `mobile/src/domain/split-calculator.ts` (`calculateSplits`)
- Exact splits need an amount for every participant and none for anyone else, each within the currency's precision, summing exactly to the total. `mobile/src/domain/split-calculator.ts`
- Share and percentage splits need a positive weight for every participant and none for anyone else; percentages must total 100. Each person gets the floor of their exact share, then leftover units go one each by largest remainder, with UUID order breaking ties. The weights are stored on the split rows. `mobile/src/domain/split-calculator.ts`, `mobile/src/domain/decimal.ts` (`allocateMinor`)
- Starting percentages split 100.00 equally with the same lowest-UUID remainder rule, so three people get 33.34, 33.33, 33.33. `mobile/src/domain/split-calculator.ts` (`equalPercentages`)
- Payers use the same equal and exact rules. Other payer modes are refused. `mobile/src/domain/payment-calculator.ts`
- Balances are worked out per container. For each live expense, each person's net is what they paid minus what they owe. Debtors are taken in UUID order. Each debtor's shortfall is shared across the creditors in proportion to what each creditor is still owed, in whole minor units by largest remainder, ties to the lower creditor UUID. Every creditor ends up owed exactly their surplus. `mobile/src/domain/balance-engine.ts` (`distributePairs`)
- A pair balance is keyed by the two person UUIDs sorted (lo, hi). A positive amount means hi owes lo. A live payment from A to B reduces what A owes B and can push it past zero. Each non-zero pair and currency comes out as two mirrored rows. `mobile/src/domain/balance-engine.ts` (`canonicalPair`, `computeBalances`)
- Simplified debts are worked out per currency (currencies alphabetically) from each person's net position: repeatedly the largest debtor pays the largest creditor, ties to the lower UUID. They're suggestions only and never change expenses, ledgers or payments. Recording one creates an ordinary payment. `mobile/src/domain/debt-simplifier.ts` (`simplifyDebts`)
- Balances are per currency. There's no conversion between currencies anywhere. `mobile/src/domain/balance-engine.ts`, `mobile/src/domain/friends-presenter.ts`
- A trip is completed when its simplified debts are empty and its last activity is at least 30 days old; otherwise it's active. A cycle of debts that cancels out doesn't keep a trip active. `mobile/src/domain/trip-state-deriver.ts`, `mobile/src/domain/trip-presenter.ts`

### Currencies

- The app ships a fixed list of currencies with code, symbol, name and decimal digits (JPY 0, most 2, BHD and KWD 3). Symbols are unique, so USD, CAD and AUD don't all show "$". An unknown code shows as its code with 2 decimals. `mobile/src/domain/currency-catalog.ts`, `mobile/src/domain/currency-data.ts`
- Currency search matches code, symbol or name, ignoring case and accents. `mobile/src/domain/currency-catalog.ts` (`searchCurrencies`)
- A new expense or payment in a trip starts in the currency of the trip's most recently created or edited live expense or payment (ties alphabetical), else the saved currency, else the phone region's currency, else INR. `mobile/src/domain/currency-defaults.ts` (`defaultCurrency`), `mobile/src/features/currency/defaults.ts` (`currencyFor`)
- Picking a currency anywhere saves it as `pref.currency` in this account's local meta. It never goes to the server. `mobile/src/features/currency/defaults.ts` (`rememberCurrency`)

### Dates

- An expense date is a calendar day string, `YYYY-MM-DD`. It shows as that day everywhere, whatever the time zone. The picker works on local noon of that day. New expenses default to today's local day. `mobile/src/lib/dates.ts`, `mobile/src/features/forms/date-field.tsx`
- Payment times, creation and edit times, and activity are instants shown in local time. `mobile/src/lib/dates.ts` (`dateTime`), `mobile/src/domain/expense-dates.ts`
- All labels are built by hand in English, so they look the same on every device. `mobile/src/lib/dates.ts`, `mobile/src/domain/expense-dates.ts`

### Trip export

- The export is a real `.xlsx` file named `{trip name} Expenses.xlsx`, with "/" and ":" turned into "-", `\ * ? " < > |` removed, cut to 60 characters ("Trip" if empty). It's written to the cache folder and shared through the share sheet. `mobile/src/features/trip/export.ts`
- Sheets, in order: Expenses, Expense Payments, Expense Splits, Settlements, Summary. Only live records appear. Expenses sort by date, payments by time; payer and split rows by name then id. `mobile/src/domain/trip-exporter.ts` (`extractExportData`, `buildWorkbook`)
- Expenses columns: Expense ID, Date, Description, Amount, Currency, Category, Paid By, Paid By Detail, Split Between, Split Detail, Payment Method, Created By, Created At, Last Edited By, Last Edited At. Expense Payments: Expense ID, Date, Description, Payer ID, Payer Name, Currency, Amount Paid, Payment Mode. Expense Splits: Expense ID, Date, Description, Participant ID, Participant Name, Currency, Amount Owed, Split Type. Settlements: Date, From, To, Amount, Currency, Note. `mobile/src/domain/trip-exporter.ts` (`buildWorkbook`)
- Summary has "Total Spent per Currency" (Currency, Total), "Per-Person Breakdown" (Person, Currency, Total Paid, Total Owed, Net) and "Net Balances Between Pairs" (Owes (From), Owed To, Currency, Amount). Net is paid minus share and leaves out payments; the pair section uses raw pair balances, payments included. `mobile/src/domain/trip-exporter.ts`
- Amounts are number cells written from exact decimals with at least two decimals. Text cells are shared strings with XML escaping. Dates and times are in the phone's local time. Unknown people show as "Unknown". `mobile/src/domain/workbook-xlsx.ts` (`xmlDecimal`), `mobile/src/domain/trip-exporter.ts`

### Splitwise import rules

- The parser strips a leading byte-order mark and reads one record per line, with quoted fields and doubled quotes. The header must start with Date, Description, Category, Cost, Currency (case-insensitive). The other non-blank header names are the people; a blank header cell is skipped without shifting the columns after it, and a repeated name is merged and warned about. `mobile/src/domain/splitwise-import.ts` (`parseSplitwise`)
- Blank rows and "Total balance" rows are skipped. A row needs a `YYYY-MM-DD` date and a positive plain decimal cost. An unreadable person cell skips the row. `mobile/src/domain/splitwise-import.ts`
- A row with category "Payment" or description "Settle all balances" becomes a payment when exactly one person is up and one is down: the one up paid the one down the cost. Otherwise it's imported as an expense with a warning. `mobile/src/domain/splitwise-import.ts`
- Expenses are rebuilt from each person's net: people who are down owe their shortfall and paid nothing; people who are up split what's left of the cost in proportion to their surplus, and paid their net plus that share. Leftover units go by largest remainder, then name. Rounding drift goes to the largest payer, with a warning above two minor units. A row with nobody up or down is paid in full by the first person. This reproduces each person's net, not necessarily the original split. `mobile/src/domain/splitwise-import.ts` (`reconstructImport`)
- An imported expense's description is trimmed and cut to 200 characters; a blank one becomes "Imported expense". `mobile/src/domain/splitwise-importer.ts` (`mapSplitwiseRows`)
- Warnings: "Duplicate person names in the header are merged into one person.", `Unreadable date "{date}"; row skipped.`, "Unreadable or zero amount; row skipped.", `Unreadable amount "{amount}"; row skipped.`, `Payment row "{description}" wasn't a two-person transfer; imported as an expense.`, "Row has no balances; recorded as paid in full by {person}.", "Row doesn't balance (no payer); skipped.", "Row doesn't balance (debts exceed the amount); skipped.", "Row's amounts didn't sum cleanly; adjusted by {amount} to balance." and "Row's amounts don't balance; skipped." `mobile/src/domain/splitwise-import.ts`
- Imported expenses keep their date, description, currency and total, pay by Card, use exact split rows, and use equal payment mode only when one person paid the whole amount. Payments carry no note. `mobile/src/domain/splitwise-importer.ts` (`mapSplitwiseRows`)
- Categories map by name, ignoring case: food and drink, dining out, dining, groceries, liquor, restaurant and drinks go to Food & Drink; transportation, taxi, car, gas/fuel, fuel, gas, bus/train, bus, train, plane, parking, bicycle and transport to Transport; hotel, rent, mortgage, accommodation, lodging, hostel and airbnb to Lodging; entertainment, games, movies, music, sports and activities to Activities; shopping, clothing, electronics, furniture, household supplies and gifts to Shopping; anything else to Other. `mobile/src/domain/splitwise-importer.ts` (`splitwiseCategoryID`)
- The chosen "you" becomes the user's own person. Everyone else is a pending person under their linked email, or under a placeholder `<person id>@users.tab`. Two people can't share an email. `mobile/src/domain/splitwise-importer.ts` (`mapImportPeople`)

### Sign-out and account deletion

- Sign-out removes this phone's push registration, stops sync, closes and deletes the user's local database, deletes their waiting receipt photos, and deletes the older iOS app's saved session. If the store held imported older iOS data, that app's files go too. Then it signs out on the server, or just locally when offline. `mobile/src/data/auth.ts` (`signOut`, `wipeLocal`)
- Account deletion calls the `delete-account` edge function with no body. Only after it succeeds does the app wipe local data and sign out locally. `mobile/src/data/auth.ts` (`deleteAccount`)
- On the server, deletion erases containers nobody else ever joined, with their records and receipt files. In shared trips the user's person rows get an `@account-deleted.invalid` email and keep their name for history, push devices and mutes are deleted, the profile becomes "Deleted user", and the auth user is deleted. `supabase/sql/20_account_deletion.sql`, `supabase/functions/delete-account/index.ts`

### Legacy handoff

The app replaces an older iOS app with the same bundle id. On iOS it picks up what that app left on the phone, so an upgrade stays signed in and keeps unsynced work. `mobile/src/data/legacy/README.md` has the details.

- With no saved session, the app reads the older app's session from the Keychain (service `supabase.gotrue.swift`, account `sb-<first part of the Supabase host>-auth-token`) through a local native module, refreshes it, checks the account matches, then deletes the Keychain item. Any failure leaves the item in place and shows sign-in. `mobile/src/data/legacy/session.ts`, `mobile/src/data/legacy/startup.ts`
- After the store opens, the older app's database (`Library/Application Support/default.store`) is copied and read without touching the original. Every row is imported with its ids, acknowledged write ids, soft deletes, ledgers, mutes and activity read state. Waiting receipt photos are copied into the waiting folder and marked pending. A waiting read cursor is taken from the older app's preferences. Rows and an import marker commit together; then the originals are renamed with `.expo-imported-v1`. `mobile/src/data/legacy/import.ts`, `mobile/src/data/legacy/convert.ts`, `mobile/src/data/legacy/preferences.ts`
- If it can't tell which account the data belongs to, or it fails, it logs a warning, the app carries on, and it tries again next launch. `mobile/src/data/session.tsx`, `mobile/src/data/legacy/import.ts` (`importLegacyData`)
- Android does none of this. `mobile/src/data/legacy/session.ts`, `mobile/src/data/legacy/import.ts`

### Platform differences

- Sign in with Apple is iOS only. Google signs in natively on iOS and through the system browser on Android. `mobile/src/app/sign-in.tsx`, `mobile/src/data/auth.ts` (`signInWithGoogle`)
- Push notifications, the app icon badge and the legacy handoff are iOS only. `mobile/src/data/push.ts`, `mobile/src/data/legacy/`
- The date picker is the compact inline picker on iOS and the system dialog on Android. `mobile/src/features/forms/date-field.tsx`
- Menus show SF Symbols on iOS and plain items on Android. `mobile/src/ui/menu.tsx`
- Forms move up for the keyboard with padding on iOS; Android resizes the window. `mobile/app.config.ts` (`softwareKeyboardLayoutMode`), screens using `KeyboardAvoidingView`
- iOS opens `tab-it.app` links through associated domains. Android declares an auto-verified link filter for `https://tab-it.app/join/`, but `site/.well-known/` has no `assetlinks.json` yet, so Android can't verify it. `mobile/app.config.ts`, `site/.well-known/apple-app-site-association`
- Android blocks the microphone and contact-writing permissions. `mobile/app.config.ts` (`blockedPermissions`)
- The bottom spacing under scrolling content follows the iOS safe area, and is a fixed 16 points on Android. `mobile/src/ui/primitives.tsx` (`useTabBarClearance`)

### Permissions and privacy

- The app asks for: notifications (iOS), the camera and photo library for receipts, and the system contact picker, which returns only the chosen contact without reading the address book. `mobile/app.config.ts` (plugins), `mobile/src/features/people/contacts.ts`
- It includes no analytics, advertising or crash-reporting SDK. `mobile/package.json`

### Server contract the client relies on

- Tables the app reads: `visible_profiles`, `trips`, `trip_people`, `categories`, `expenses` with `expense_payments` and `expense_splits`, `settlements`, `trip_mute_prefs`, `activity_log`. Direct writes: trip updates, settlement upserts and updates, expense delete updates, mute upserts and deletes, and the user's own `push_devices` delete. Everything else goes through RPCs. `mobile/src/data/remote.ts`, `mobile/src/data/sync.ts`, `mobile/src/data/push.ts`
- RPCs the app calls: `ensure_current_profile`, `create_trip_with_self`, `add_trip_person_by_email`, `update_trip_person_email`, `remove_trip_person`, `claim_trip_people_for_current_email`, `create_expense_with_payments_and_splits`, `resolve_or_create_non_group_container`, `get_or_create_trip_invite`, `revoke_trip_invite`, `join_trip_with_invite`, `mark_activity_seen`, `activity_read_cursor`, `register_push_device`. The one edge function it calls is `delete-account`. `supabase/sql/02_profiles.sql`, `supabase/sql/14_rpc_trip_creation.sql` to `supabase/sql/21_trip_invites.sql`
- Limits: money is `numeric(20,8)` (twelve whole digits); expense and payment amounts are positive and ledger amounts not negative; currency is three upper-case letters; names are 1 to 60 characters; a trip name is 1 to 100; email at most 320 with an "@"; expense description 1 to 200; payment note at most 200; receipt path at most 512. `supabase/sql/02_profiles.sql`, `supabase/sql/03_trips_people.sql`, `supabase/sql/05_expenses.sql`, `supabase/sql/08_settlements.sql`
- Each live expense has at least one payment and one split, and each ledger sums exactly to the amount, checked at the end of the transaction. Every person named must belong to the trip, removed people included. A payment's two people must differ. Trip kind and creator, and an expense's or payment's trip and creator, never change. `supabase/sql/06_expense_payments.sql`, `supabase/sql/07_expense_splits.sql`, `supabase/sql/08_settlements.sql`, `supabase/sql/05_expenses.sql`
- The expense RPC sets the creator to the caller on insert, keeps it on edit and sets the editor to the caller. If the sent write loses, it changes nothing and still succeeds, so success doesn't mean this version won. `supabase/sql/16_rpc_expenses.sql`
- Access to a trip needs a joined, not-removed person row for the caller. A pending email gives no access. Members can edit and delete each other's expenses and payments. Deleted rows stay readable to members, so the app pulls them and hides them. `supabase/sql/01_private_helpers.sql` (`is_trip_member`), `supabase/sql/12_rls.sql`
- `set_sync_fields` on the server applies the same conflict rules as the app: delete wins, then later `updated_at` (or `deleted_at` between deletes), then the larger write_id. An update that loses affects zero rows without an error. An update that leaves `write_id` unchanged gets a fresh server stamp. `supabase/sql/00_extensions.sql`
- The server bumps a trip's `last_activity_at` on expense and payment writes. `supabase/sql/05_expenses.sql` (`touch_trip_last_activity`)
- `purge_soft_deleted_records`, meant to run on a schedule with the service role, hard-deletes expenses, payments and categories deleted more than 30 days ago, and deleted trips past that age once no expense or payment rows remain in them. Nothing in the app restores deleted records. `supabase/sql/11_maintenance_realtime.sql`
- Realtime publishes `trips`, `trip_people`, `expenses` and `settlements`. `supabase/sql/11_maintenance_realtime.sql`
- The receipts bucket is private, JPEG only, 10 MB at most. Current members can read an object whose path matches a live expense's stored path; only that expense's creator can write it. `supabase/sql/13_receipt_storage.sql`, `supabase/sql/01_private_helpers.sql`
- The read cursor only moves forward and can't pass the server's clock. `supabase/sql/02_profiles.sql` (`mark_activity_seen`)
- A profile rename is copied onto that user's joined trip person rows by the server. `supabase/sql/02_profiles.sql` (`sync_profile_name_to_trip_people`)
