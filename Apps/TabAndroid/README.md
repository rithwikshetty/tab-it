# tab Android

Native Android client for tab. This is an independent Gradle build inside the
same repository as the existing iOS app.

## Toolchain

- JDK 17
- Android Gradle Plugin 9.3.0
- Gradle Wrapper 9.5.0
- Kotlin 2.4.10
- Compose BOM 2026.06.00
- Room 2.8.4 with KSP 2.3.9
- Supabase Kotlin 3.6.0 behind `:core:sync`
- Navigation Compose 2.9.8 with lifecycle-aware ViewModels
- compile SDK 37, target SDK 36, minimum SDK 26

On the current Homebrew-based macOS setup:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

## Checks

```bash
cd ../..
bash supabase/scripts/configure_android_local.sh
bash supabase/scripts/connect_android_emulator.sh
cd Apps/TabAndroid
./gradlew test
./gradlew lint
./gradlew assembleDebug assembleRelease
./gradlew connectedDebugAndroidTest
```

The pure Kotlin `:core:domain` module contains the same accounting and sync
rules as Swift `TabCore`: currency precision, split/payment calculation,
multi-payer balances, debt simplification, conflict resolution, trip state and
analytics, cross-container balances, and Splitwise import. Both platforms run
the shared cases in `contracts/domain/parity-v1.json`.

The Android-only `:core:data` module owns Room, observable local repositories,
the exact-decimal ledger transaction, receipt drafts, and the ordered sync
outbox. Its versioned schema is exported under `core/data/schemas/`. Debug
builds seed only fictional local rows; release builds start empty.

The Android-only `:core:sync` module owns local authentication, typed Supabase
transport, snapshot-to-Room conflict handling, ordered outbox delivery, retry
backoff, current-trip realtime refresh, invitation RPCs, and private receipt
Storage. The community-maintained Supabase Kotlin dependency stays behind the
`RemoteGateway` interface.

The app is a single-activity Compose client with manual dependency injection,
screen-level state held by `TabViewModel`, and Room-backed flows collected with
Android lifecycle awareness. The current shell restores local sessions, signs
in to the fictional local account, provides Friends, Trips, Activity and
Settings destinations, and supports Room-first trip create, rename and archive.
Sign-out first requires a successful sync, then clears that account's local
copy so a later account cannot see stale data.

Trip detail is also Room-backed. It exposes expenses, per-currency trip totals,
active or invited people, pair balances, simplified repayment suggestions, and
settlement history. Expense create and edit support exact decimal amounts,
currency, category, date, payment method, multiple payers, and equal or exact
splits; save and delete are local-first outbox operations. Settlement create,
edit, and delete use the same Room-first outbox boundary. Receipt images are
downsampled and converted to JPEG in app-private storage, then the expense is
created before the authenticated private-bucket upload required by Storage RLS.

Friends aggregates each signed-in user's position across trip and non-group
containers without converting currencies. Friend detail breaks a balance down
by source and routes repayment suggestions back to the standard settlement
form. The people-first friend expense flow resolves the existing server-managed
non-group container through the local RPC, then uses the same expense editor as
a trip. Member add and remove also use the existing Supabase RPCs, so these
operations require the disposable local service to be running.

Activity is pulled into Room and presented with per-user unread and mute rules.
Read state is acknowledged through `mark_activity_seen`. Trip members can share
or revoke an invite link, and signed-in users can join with the same web-link
token contract used by iOS.

Trip detail exports a deterministic exact-decimal CSV through Android's share
sheet. Settings imports Splitwise group CSVs up to 5 MB: parsing and preview are
local, the user maps their identity, and apply uses the same Room-first trip,
expense, settlement, and member boundaries as normal editing. Failed imports
archive their partial trip instead of leaving an active half-import.

The generated and ignored `local.properties` points debug builds at
`http://127.0.0.1:54321`. The emulator connection script creates an ADB reverse
mapping to the guarded local Supabase API. It refuses physical devices and
requires exactly one ready emulator. Release builds contain no backend URL or
key and explicitly remove the Internet permission. Runtime validation refuses
hosted Supabase URLs and privileged keys; there is no production fallback.

Use the `Tab_API_36` Android 16 emulator for local device tests.

The local client is feature-complete for the agreed Android scope. Production
enablement is deliberately separate: real release authentication, a
non-production compatibility rehearsal, verified app links, notification
delivery, signing/distribution, monitoring, account-deletion UX, physical-device
coverage, and explicit production approval remain release-readiness work.
