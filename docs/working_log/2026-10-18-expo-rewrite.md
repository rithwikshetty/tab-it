# Expo rewrite of the iOS and Android clients

## Goal

Replace the SwiftUI iOS app and the Kotlin/Compose Android app with one Expo / React Native app that keeps every feature, talks to the unchanged Supabase contract, and ships as an update to the live iOS app. Production Supabase stays untouched. Work is pushed to `main` as it lands.

## Log

### 2026-10-18 morning: analysis and decision

- Two native clients duplicated the domain (TabCore in Swift, `:core:domain` in Kotlin), sync, and every screen, about 41k lines in total. Android was mid-way through a phased plan.
- Decision: Expo SDK 58 (RN 0.88, Hermes, New Architecture) with Expo Router, keeping the app offline-first: an in-memory store mirrored to per-user SQLite, and one TypeScript sync engine that follows the server's LWW rules (delete wins, later `updated_at`, larger `write_id`).
- Sol wrote `docs/specs/client-functional-spec.md`, a parity checklist taken from the Swift app, and ported TabCore and the presenters to `mobile/src/domain` with the parity fixtures. Hermes constraints: no `Intl` in the domain, no `new URL` parsing.

### 09:37 to 09:58: app, screens, first simulator pass

- `0647153`, `7af757d`: store, merge, sync, auth (Apple, Google with PKCE, email code), push (iOS/APNs only, matching the server), realtime, receipts, and every screen.
- PostgREST returns numeric columns as JSON numbers, so money columns are selected with `::text` casts.
- `5025959`: the first simulator pass found these, all fixed. The FAB sat under the iOS floating tab bar, the amount input clipped digits, errors showed twice, and an empty-state message was duplicated.

### 10:07: Astra review round 1

- Twelve findings, eleven fixed in `e2b90cb`. They covered store op ordering, a stopped engine still writing, settlement update vs upsert under RLS, receipt overwrite races, the sign-out inventory, unacknowledged deletes, zero-row updates, server-adopted people, referenced people on pull, and activity cursor scheduling. Rounding of over-precise server decimals was left as is, because every client writes minor units only.
- The Swift-upgrade handoff (finding 2) went to Sol.

### 10:11 to 10:20: Android pass, native apps removed

- `1f198e2`: Android header title collision, hidden tab labels, md tab icons (needed `expo-symbols`).
- `9bbf17d`: removed `Apps/` and `Packages/TabCore`. Mistake: `rm -rf Apps` also deleted the git-ignored `Apps/Tab/Config/Secrets.xcconfig` and the APNs key `AuthKey_ADL6269Z26.p8`. The key was recovered from a scratch copy into `.secrets/` (git-ignored). The production values in `Secrets.xcconfig` were not recoverable locally; the URL is known and the publishable and Turnstile keys come from their dashboards.
- `2f75a1f`: a friend pending in one trip and joined in another showed twice; pending emails now resolve to the joined account.
- `d8e427b`: the local stack emails a code, like the deployed project, so email sign-in was tested end to end through Mailpit. A new user (Riya) signed up on Android and was claimed into her pending trip.

### 10:23: Swift upgrade handoff (Sol)

- `6008609`: a small iOS module reads the Swift app's Keychain session (`supabase.gotrue.swift`, account `sb-<host label>-auth-token`), refreshes it into a new session, and imports unsynced SwiftData rows and receipt photos before sync starts. The old item is deleted only after the new session is saved.
- Still unproven: a signed device update over the installed App Store build. The simulator can't show Keychain access groups or the real data container.
- `b9118ee`: Hermes has no `crypto.subtle`, so auth-js sent Google sign-in a plain PKCE challenge. expo-crypto now backs `digest`.

### 10:26 to 10:44: remaining flows end to end

- Another session started using the shared simulator (`com.gleeds.assist.dev`). Testing moved to a new simulator, "tab-it test" (`06997F7F-…`).
- Avatars: one person changed colour from trip to trip because tones came from the per-trip row. `personTone` now colours by account, then email (`5d39cf6`).
- Invite link: created on iOS and opened on Android, where it joined, and the join reached iOS by realtime. Deleting the trip on iOS showed "Trip not found" on Android, but the not-found state kept the old header (`63ad57a`).
- Receipt: attached on Android, uploaded (87 KB from 152 KB), and loaded on iOS through a signed URL. A trip opened after a change had to wait for the 5-minute poll; subscribing now pulls once (`d3c25a2`).
- Export: a valid five-sheet workbook with correct balances, but audit times were in UTC where the spec says local (`aa6fb61`).
- Splitwise import: the totals match the CSV's own total-balance row. "1 payments" copy fixed (`147fec2`).

### 10:53: Astra review round 2

Seven findings, all confirmed against the code and fixed in `1c285b5`.

- The store kept a change in memory when its SQLite write failed, so sync could push it and a later acknowledgement could persist only part of it. Fixed at the store, not only on the import path. A failed write restores the touched keys from disk unless a later commit changed them.
- `File.move` and `File.write` return promises in SDK 58, and two calls weren't awaited.
- `saveExpense` read the store before awaiting photo processing, and deleted the old photo before the new one was safe.
- An upload could start after sign-out stopped the engine.
- Sign-out left the Swift Keychain item and imported Swift files behind.
- A refused delete of an unacknowledged row was forgotten.
- While re-testing, a Metro reload mid-save left an orphan photo file. The store now prunes photo files no expense refers to when it opens.
- Round 3 was requested on the store restore logic.

### 11:05: Astra review round 3

Five findings on the round-2 fixes, all confirmed. Fixed in `8ea0c81`.

- Restoring individual keys after a failed write couldn't tell a later removal or metadata write from the failed one. An identical queued write also reported success. Replaced with a simpler rule: on failure, reload all memory from disk and fail every commit made before the reload finished, no-op commits included. A failure is rare (a full or broken disk), so failing a few unrelated commits is the safer trade.
- That rule also covers a failed photo save whose file an ack had copied a reference to: the ack is queued behind the failure, so it fails too.
- Waiting photos were in one folder shared by all accounts. An expired session followed by another account's sign-in would have pruned the first account's unsent photos. Now each account has its own folder.
- The uploader deleted a photo before saving the completion. It now deletes after, so a failed save retries the upload instead of reporting a missing photo.
- Testing note: when Metro restarts, a running app keeps its old bundle until it's relaunched. The first re-test ran stale code; after relaunching Android, the photo staged into the account folder, uploaded, and was cleaned up after the save.
- Round 4 was requested on the new store rule.

### 11:15: Astra review round 4

Two findings on the new store rule, both confirmed and fixed.

- If reloading from disk also failed, the store logged it and kept accepting writes on top of unsaved memory. It now refuses further writes until the app restarts.
- The generation was bumped after listeners were notified of the reload, so a listener's write was wrongly rejected. It's now bumped first, and notifying happens outside the reload's error handling.
- 418 tests pass, typecheck and Prettier are clean. Nothing new to review: both changes are what the review asked for.

### 11:35: production config for TestFlight

- Google sign-in: the old Google Cloud project (`tab-it-498309`) sat under a closed billing account and couldn't be opened, so the user had it shut down (deleted after 17 Nov 2026). A new project `tab-it-512005` (rithwikshetty96@gmail.com) has an External consent screen published to production (basic scopes, no logo, so no verification needed) and a Web OAuth client "Supabase auth". Its redirects are the production and local Supabase callbacks. The ID and secret are in git-ignored `.secrets/google-oauth-client.json`.
- Production Supabase, changed with the user's explicit approval: the Google provider was already enabled, but pointed at the old client, so it was broken. It now uses the new client, confirmed by reading it back and by `/auth/v1/authorize?provider=google` redirecting to the new client ID. The `com.rithwikshetty.tab://auth-callback` redirect was already allowed, so that setting was left alone. The Supabase MCP has no Auth config tools, so these changes went through the dashboard.
- The Google button sits behind `EXPO_PUBLIC_GOOGLE_SIGN_IN` (`ff19a92`).
- `mobile/.env.production.local` (git-ignored) holds the production values. The publishable key and Turnstile site key match the Info.plist of the live 1.3.0 (16) Xcode archive. The email OTP length is 8.

### 13:40: Apple team, phone build, TestFlight blocked

- The first archive failed with "No Account for Team KR8C647GCW". That ID is in the development certificate's name, not the team. The real team is `36VWCMM6GL`, confirmed from the certificate's OU and the live 1.3.0 archive (`504d047`). The deployed `apple-app-site-association` had the wrong ID too, so invite links never opened the app. `site/` was redeployed with the fix and the privacy policy dated 18 July 2026.
- Add expense sat about 62pt too high on iOS. Inside NativeTabs, the screen's bottom safe area already reaches the top of the floating tab bar, and `useTabBarClearance` was adding the tab bar height again (`d2c84a2`).
- An ad hoc export (`release-testing`) of 2.0.0 (17), with production config and signing, is installed on the user's iPhone 16.
- The user accepted the updated Program License Agreement and filled in the EU DSA declaration as a non-trader. App Store Connect still shows the agreement banner, the Free Apps Agreement reads "Active (New Agreement Available)" with nothing to accept, and every upload fails with "You do not have required contracts". Sol checked through the user's own browser and found nothing pending. Uploads have been retried every 5 to 15 minutes since 12:13. Apple forum reports of the same state say to wait about 24 hours, then phone Developer Support to have the acceptance pushed through. The App Store Connect business address still shows the user's old UK address, which matches one reported cause.

### 19 Oct 16:24: build 17 uploaded

- The contract block cleared on 19 October. The upload of 2.0.0 (17) succeeded at 16:24 and the build went into App Store Connect processing.

### 19 Oct 18:30: native Google sign-in on iOS, build 18

- The Google consent page named `gaseuxsieddlksxtdliq.supabase.co`, because the browser flow returns through the Supabase callback. iOS now signs in with `@react-native-google-signin/google-signin` and passes the ID token to `signInWithIdToken`, the same shape as Sign in with Apple. Android keeps the browser flow.
- The library's free iOS API takes no nonce, and the GoogleSignIn SDK otherwise adds a random one Supabase can't check. A patch-package patch passes a SHA-256-hashed nonce through to `signInWithPresentingViewController:hint:additionalScopes:nonce:completion:`, so "Skip nonce checks" stays off.
- Google Cloud project `tab-it-512005` has a new iOS OAuth client "tab iOS" (bundle `com.rithwikshetty.tab`, team `36VWCMM6GL`, App Store ID 6770451955). Its public client ID is `GOOGLE_IOS_CLIENT_ID` in `src/lib/config.ts`, repeated in `app.config.ts` because Expo can't import TypeScript modules there. Expo prebuild loads `.env.development.local` even with `NODE_ENV=production`, so the ID can't come from the production env file.
- Production Supabase, changed with the user's explicit approval through Codex in the user's Chrome: the Google provider's Client IDs field went from the web client alone to the web client followed by the iOS client, confirmed after a reload. Nothing else on the page changed; "Skip nonce checks" is off.
- Google branding (name `tab-it`, no logo) is unverified, so Google doesn't show it to users yet.
- Codex review: no findings. Build 2.0.0 (18) archived, installed ad hoc on the user's iPhone, and uploaded to App Store Connect.
