# Installed iOS app handoff

Exports from `@/data/legacy`:

- `restoreLegacySession(): Promise<string | null>` returns a refresh token without removing its saved item. The native query mismatch below requires a bridge for installed Swift sessions.
- `clearLegacySession(): Promise<boolean>` clears the item restored through SecureStore. Call only after successful refresh and durable JS session persistence.
- `importLegacyData(store, userId, { legacyUserId? }): Promise<LegacyImportResult>` always resolves. Status is `imported`, `already-imported`, `not-found`, `unsupported`, `account-mismatch`, or `failed`.

## Integration

In `../session.tsx:53`, await `getSession()`. When no JS session exists, await `restoreLegacySession()`, then `supabase.auth.refreshSession({ refresh_token })`. Keep loading until this finishes. Clear the old item only after the new session is durably saved. Preserve it on failure. The native bridge must also return the old `user.id`.

After `openStore(userId)` at `../session.tsx:73`, await `importLegacyData(store, userId, { legacyUserId })` before publishing the store, constructing/starting sync, or claiming people. Recheck cancellation afterward. Make effect cleanup wait for import before closing the store. Surface failed/ambiguous imports without crashing or deleting data, and retry next launch.

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

Add a local Expo native module using `SecItemCopyMatching` with the exact class, service, and string account above, `kSecReturnData = true`, and `kSecMatchLimitOne`. Omit the generic attribute and explicit access group. Return the decoded refresh token and `user.id`. Add a separate native delete method with the same query, called after refreshed-session persistence. Wire this fallback into `session.ts` here. Until then, native sessions remain untouched and users must sign in again. Node auth tests prove the JS contract only.

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
- SQLite REAL may already have lost Swift Decimal precision; casting cannot recover those bits. The archived original remains available.
- Unknown/corrupt schemas retain the source files. General UserDefaults preferences, queued invites, APNs registration, signed-URL caches, and data removed by sign-out/uninstall are outside this import.
- A signed device update, native Keychain reader, Expo runtime import, and old/new sync convergence remain release checks. No hosted backend or production data was used.

The fictional fixture was captured on iPhone 18 Pro `649BB472-E327-412F-B750-CC52DB177743`. The old app was built from a `/tmp` copy using XcodeGen and xcodebuild with `TAB_SUPABASE_URL=http://127.0.0.1:54321` and `TAB_SUPABASE_PUBLISHABLE_KEY=local`; the built Info.plist was verified. Launch used mock auth and both requested seed flags. Because the demo seed marks some parents clean, the scratch build also ran `fixtures/seed.swift` after `DemoScreenshotSeed` to add dirty parents and missing edge cases. The fixture is a checkpointed backup taken after termination. The app was uninstalled and that simulator shut down; iPhone 16 was untouched.

From `mobile/`, with Node supporting `node:sqlite`:

```sh
npx vitest run src/data/legacy
npx tsc --noEmit
```

Tests cover the native fixture and real Node SQLite/filesystem adapters, including ledger totals, large amounts, WAL recovery, repeat/concurrent import, disk failure, closed stores, account isolation, receipts, and activity state. ESLint was unavailable in the installed dependencies. Changes are confined to this directory; session wiring is left to the integrating agent.
