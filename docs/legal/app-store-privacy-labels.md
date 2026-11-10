# App Store Connect: App Privacy ("nutrition label") answers

Fill these in App Store Connect → App → App Privacy. Answers reflect what the app
actually sends off-device as of 2026-11-10 (Supabase backend, Cloudflare Turnstile
on email-code sign-in, no analytics, no ads, no tracking SDKs). Re-audit before
submission if new data flows are added (e.g. crash reporting, analytics).

## Top-level question

**Do you or your third-party partners collect data from this app?** → **Yes**

## Data types collected

All collected data is **Linked to the user's identity** (it is keyed to their
account) and used **only for App Functionality**. Nothing is used for tracking,
advertising, or analytics. Answer **No** to "Do you use this data for tracking?"
for every type.

| ASC category | ASC data type | What it actually is |
|---|---|---|
| Contact Info | Name | Display name from Apple/Google/email sign-up; names of people added to trips |
| Contact Info | Email Address | Account email (or Apple private relay); emails of people added to trips |
| User Content | Photos or Videos | Receipt photos attached to expenses |
| User Content | Other User Content | Trip names, expense descriptions/amounts, settlements |
| Identifiers | User ID | Supabase account UUID |
| Identifiers | Device ID | APNs push token stored server-side for notifications |

## Explicitly NOT collected (answer No / leave unchecked)

- Health & Fitness, Financial Info (no bank or card data; amounts are user content),
  Location, Sensitive Info, Contacts (only the email of the one contact the user
  picks leaves the phone; the address book is never uploaded), Browsing History,
  Search History, Usage Data, Diagnostics, Purchases, Audio Data.

Note on "Contacts": Apple's category means collecting the user's address book.
The app shows the system contact picker (`Contact.presentPicker()` in
`mobile/src/features/people/contacts.ts`), then reads the picked contact's name
and email addresses. That read needs Contacts access, so the app declares
`NSContactsUsageDescription` (the `expo-contacts` plugin in
`mobile/app.config.ts`) and iOS asks the user for it. Only the email the user
chooses is stored and sent, and it is covered under Contact Info → Email
Address. The address book itself is never sent, so "Contacts" stays unchecked.

Note on Turnstile: requesting an email sign-in code runs Cloudflare Turnstile
in a web view (`mobile/src/features/auth/turnstile.tsx`). Cloudflare sees the
device's IP address and browser signals to tell a person from a bot. The
privacy policy discloses this. Confirm with the App Privacy definitions whether
it needs its own entry before the next submission.

## Privacy policy URL

The policy is `site/privacy.html`, served at `https://tab-it.app/privacy`.

## Account deletion review note

Reviewer-facing note (App Review Information): account deletion is in
Settings → Delete account, available to every signed-in user without contacting
support. This satisfies guideline 5.1.1(v).
