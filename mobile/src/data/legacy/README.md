# Installed iOS app handoff

Exports from `@/data/legacy`:

- `restoreLegacySession(): Promise<LegacySession | null>` returns `{ refreshToken, legacyUserId }` without removing the saved item. Missing or invalid tokens and user IDs return `null`.
- `clearLegacySession(): Promise<boolean>` deletes the native item that was restored. Call only after successful refresh and durable JS session persistence.
- `importLegacyData(store, userId, { legacyUserId? }): Promise<LegacyImportResult>` always resolves. Status is `imported`, `already-imported`, `not-found`, `unsupported`, `account-mismatch`, or `failed`.

## Integration

`../session.tsx` uses `startup.ts` to await `getSession()`. With no JS session, it awaits `restoreLegacySession()`, then `supabase.auth.refreshSession({ refresh_token })`. The installed auth client awaits its storage writes before resolving refresh. The restored account must match the refreshed session before the native item can be cleared. Failures preserve that item and show sign-in without logging token contents.

Startup stays loading through auth notifications and the handoff. The wait limits are 10 seconds for the saved JS session, 3 seconds for a native read, 15 seconds for refresh, and 3 seconds for clearing. An existing JS session has a separate 3-second limit for reading legacy account evidence. Overlapping startup calls share the same promise to avoid duplicate refreshes.

Before native deletion, `clearLegacySession()` saves the legacy user ID in SecureStore under `legacy.swiftData.userId.<account-key>`. This preserves account evidence for import retries after the token has moved to JS storage. `legacyImportUserId()` reads it on later launches, falling back to a retained native session. A failed account-evidence write prevents native deletion.

After `openStore(userId)`, the provider awaits `importLegacyData(store, userId, { legacyUserId })` before publishing the store, constructing/starting sync, or claiming people. It rechecks cancellation afterward, and cleanup waits for opening and import before closing the store. Failed or ambiguous imports log a warning and allow normal use; they retry next launch. A pending claim request does not delay store cleanup. The `signedIn` object remains stable across token refreshes.

Signing out calls `forgetLegacySession()`, which deletes the Swift Keychain item whether or not this launch restored it, so a signed-out phone stays signed out. When the store being wiped carries the import marker, `discardImportedLegacyFiles()` also deletes the Swift database, its pending photos and their archives; that data was in the store the user chose to discard, and leaving it would import it again on the next sign-in. Without the marker the originals stay for a later import into that account.

Activity uses the existing `_readAt`, `_dismissedAt`, and `activity.seenAt` fields. `activity.seenAtPushed` stays unset so normal sync acknowledges the cursor. No selector changes are needed.

## Keychain findings

The resolved Swift package is **2.46.0**, revision `dd29b624b9ceea87612d0b00457e1400f7d22c2e`. Sources were read in `~/Library/Developer/Xcode/DerivedData/Tab-chaecrqboghkkmbbaabddwvqqzxz/SourcePackages/checkouts/supabase-swift/`.

| Attribute | Value and source within that checkout |
| --- | --- |
| Class | `kSecClassGenericPassword`, `Sources/Auth/Internal/Keychain.swift:57` |
| Service | `supabase.gotrue.swift`, `Sources/Auth/Storage/KeychainLocalStorage.swift:8` |
| Account/key | `sb-<first hostname component>-auth-token`, `Sources/Supabase/SupabaseClient.swift:178`; Swift string account, `Sources/Auth/Internal/Keychain.swift:63` |
| Generic attribute | Absent, `Sources/Auth/Internal/Keychain.swift:55-72` |
| Accessibility | `kSecAttrAccessibleAfterFirstUnlock`, `Sources/Auth/Internal/Keychain.swift:85` |
| Value | Raw UTF-8 JSON, `JSONEncoder().encode(session)`, `Sources/Auth/Internal/SessionStorage.swift:65-70`; camelCase `refreshToken`, `Sources/Auth/Types.swift:79` |

The app supplies no custom storage or access group, `Apps/Tab/Sources/Tab/Services/SupabaseClientProvider.swift:8`. The production hostname was not read from Secrets.xcconfig. The runtime key is derived from Expo's configured URL without contacting it.

**SDK 58 SecureStore cannot query the Swift item.** Its queries require a generic attribute and a byte-valued account, `mobile/node_modules/expo-secure-store/ios/SecureStoreModule.swift:186-198`. Swift sets a string account and no generic attribute. SecureStore tries service suffixes `:no-auth` and `:auth`, then the original service, lines 82-90. Accessibility options cannot change these attributes.

`mobile/modules/legacy-keychain/` is a local Expo Modules API module. Its Swift `readLegacySession(service, account)` uses `SecItemCopyMatching` with the exact class, service, and string account above, `kSecReturnData = true`, and `kSecMatchLimitOne`. Its separate `deleteLegacySession(service, account)` uses the same identifying attributes. Neither query includes a generic attribute or access group. JS decodes the raw UTF-8 JSON into the refresh token and `user.id`. The module no-ops on Android and in binaries without the native module. Expo discovers it through the default `modules/` autolinking directory, without a dependency or config-plugin entry.

Preserve bundle `com.rithwikshetty.tab`, team `KR8C647GCW`, signing access groups, and callback identity. Test an update over the installed app; uninstalling removes its data container.

## Data findings and guarantees

`Apps/Tab/Sources/Tab/Services/TabModelContainer.swift:12-14` uses default configuration; `LocalStore.swift:11-21` wipes models on sign-out. The simulator confirmed `Library/Application Support/default.store` plus SQLite WAL/SHM sidecars. `fixtures/schema.txt` records the ten actual model tables; `fixtures/provenance.json` records encodings, counts, hash, and capture settings.

UUIDs are 16-byte blobs in UUID order. Timestamps are seconds since 2001-01-01 UTC; conversion keeps microseconds and UTC expense calendar days. Relationships use integer `ZTRIP`/`ZEXPENSE` references to parent `Z_PK`. Money has SQLite NUMERIC affinity, physically INTEGER or REAL. SQL emits full-precision text for REAL amounts and exact text for INTEGER amounts; the existing decimal currency normaliser restores known minor-unit scales without JS money numbers. Unknown currency codes retain their decimals without assuming a scale.

All model rows are imported, including clean rows. IDs, acknowledged write IDs, soft deletes, people, complete expense ledgers, settlements, profiles, categories, mute/unmute state, and activity state are preserved. Newer Expo edits retain their ledgers. Missing native creation timestamps use `updatedAt` for profiles/categories, the expense creation time for payment/split rows, and `mutedAt` for mutes.

Pending JPEGs come from `Library/Application Support/ReceiptUploads/<trip>__<expense>.jpg`, `ReceiptStorage.swift:110-120`. Referenced bytes are copied to `Documents/receipts`, matching `../receipts.ts:26-34`, before commit; expenses get `_receipt: "pending"`. Conflicting destination bytes fail import and preserve both copies. Unreferenced files stay untouched.

The importer copies the store and WAL to cache, omits SHM, checks integrity, and reads a query-only transaction. SQLite never opens the original store. Expo exposes no read-only open flag, `expo-sqlite/src/NativeDatabase.ts:40`, and uses `sqlite3_open`, `expo-sqlite/ios/SQLiteModule.swift:138`. The copy therefore has a read/write handle with `PRAGMA query_only = ON`; a strict `SQLITE_OPEN_READONLY` handle needs a native SQLite bridge.

Rows and `legacy.swiftData.v1` commit atomically. Only afterward are the original store/sidecars renamed with `.expo-imported-v1`; transferred receipt originals move to `ReceiptUploads.expo-imported-v1`. Originals are never deleted. Failed store renaming retries next call. Persistence failure requires reopening the Expo store before retrying because its commit changes memory before disk.

## Limits and tests

- SwiftData has no explicit owner field. A unique self-only cursor or single cached profile identifies the account. Multiple profiles without a cursor defer until the caller supplies a native-session `legacyUserId`. Do not guess it.
- SQLite REAL may already have lost Swift Decimal precision; casting cannot recover those bits. The archived original remains on the phone until sign-out.
- Unknown/corrupt schemas retain the source files. General UserDefaults preferences, queued invites, APNs registration, signed-URL caches, and data removed by sign-out/uninstall are outside this import.
- A signed device update must prove access to the installed app's actual Keychain item, refresh-token validity, Expo runtime import, and old/new sync convergence. Unit tests and a simulator build cannot prove these upgrade behaviours. No hosted backend or production data was used.

The fictional fixture was captured on iPhone 18 Pro `649BB472-E327-412F-B750-CC52DB177743`. The old app was built from a `/tmp` copy using XcodeGen and xcodebuild with `TAB_SUPABASE_URL=http://127.0.0.1:54321` and `TAB_SUPABASE_PUBLISHABLE_KEY=local`; the built Info.plist was verified. Launch used mock auth and both requested seed flags. Because the demo seed marks some parents clean, the scratch build also ran `fixtures/seed.swift` after `DemoScreenshotSeed` to add dirty parents and missing edge cases. The fixture is a checkpointed backup taken after termination. The app was uninstalled and that simulator shut down; iPhone 16 was untouched.

From `mobile/`, with Node supporting `node:sqlite`:

```sh
npx vitest run src/data/legacy
npx tsc --noEmit
npx vitest run
npx prettier --check "src/**/*.{ts,tsx}"
npx prettier --ignore-path /dev/null --check src/data/legacy/session.ts src/data/legacy/session.test.ts src/data/legacy/startup.ts src/data/legacy/startup.test.ts src/data/legacy/native-keychain.test.ts src/data/legacy/session-provider.test.ts src/data/legacy/index.ts modules/legacy-keychain/index.ts
```

Tests cover the native fixture and real Node SQLite/filesystem adapters, including ledger totals, large amounts, WAL recovery, repeat/concurrent import, disk failure, closed stores, account isolation, receipts, and activity state. Auth tests cover exact JS bridge arguments, Android no-ops, session decoding, persistence ordering, account-evidence retention, timeouts, shared refreshes, provider auth-event buffering, import ordering, cancellation, cleanup, and stable `signedIn` identity. `.prettierignore` excludes this legacy directory, so its edited files also need the explicit formatting check above.

## Handoff validation log

### 2026-10-18

- Added the iOS keychain module and bounded session startup. Persisted legacy account evidence supports data-import retries after native token deletion. The provider waits for import before exposing the store or creating sync, and waits for import before closing a cancelled store.
- `npx tsc --noEmit` passed. `npx vitest run` passed all 410 tests across 34 files. Explicit Prettier checks passed for every edited TypeScript file. The full source formatting check passed before concurrent UI edits; its final run flags the out-of-scope `src/ui/primitives.tsx`.
- `npx expo prebuild --platform ios --no-install`, `pod install`, and `xcodebuild -workspace ios/tabit.xcworkspace -scheme tabit -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/tab-legacy-dd build` passed. The native module compiled for arm64 and x86_64, and the generated module provider registers `LegacyKeychainModule`. The built bundle ID is `com.rithwikshetty.tab`. No simulator install or launch was performed.
- Focused legacy/module ESLint checks passed using a temporary config. The provider's existing synchronous `setOpened(null)` effect triggers `react-hooks/set-state-in-effect`, also reproduced against its unchanged baseline. Expo's automatic lint setup was removed from the app dependency files and repository config.
- Signed device upgrade and real installed-session/runtime import checks remain. No hosted backend or production data was accessed.
