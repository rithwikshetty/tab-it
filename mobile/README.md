# tab-it app

One Expo / React Native app for iOS and Android. It is the App Store update to the live app: same bundle id (`com.rithwikshetty.tab`), Apple team, auth callback scheme and invite links, and it talks to the existing Supabase backend without any server change.

## Layout

```
src/
├── app/            Expo Router screens (file = route)
│   ├── sign-in.tsx, join/[token].tsx, auth-callback.tsx
│   └── (app)/      signed-in area: (tabs)/ plus trip, expense, payment, friend screens and modals
├── domain/         pure money, splitting, balances, presenters (port of the Swift TabCore); see domain/API.md
├── data/           local store, sync engine, auth, push, receipts, server-only actions
├── features/       pieces shared by several screens (ledger rows, pickers, forms)
├── ui/             theme (sage palette), primitives, avatar, menus
└── lib/            config, Supabase client, ids, date labels
```

### How data flows

1. A screen calls an action in `data/actions.ts`. The action commits rows to the local store (`data/store.ts`), which updates memory at once and writes the per-user SQLite file. The row is now "dirty": its `write_id` differs from `_pushed`.
2. The sync engine (`data/sync.ts`) notices dirty rows, pushes them in dependency order (profile, trips, people, expenses with ledgers, payments, receipts, mutes, activity cursor), and marks each acknowledged by the exact `write_id` it sent.
3. It then pulls everything visible (or one trip, for realtime updates), and `data/merge.ts` applies it with the server's rules: delete wins, then the later `updated_at`, then the larger `write_id`. Unsent local edits survive a pull unless the server's version would win anyway.

Rows keep Supabase column names, so a pulled row is stored as-is. Money is a decimal string in rows and a `bigint` count of minor units in domain maths. PostgREST money columns are read with `::text` casts so nothing passes through a float.

Things only the server can do (claiming people, invites, non-group containers, account deletion) live in `data/online.ts` and need a connection.

## Run it

Prerequisites: Node 24, Xcode, Android SDK with an emulator, Docker, Supabase CLI.

```bash
# 1. Local backend (fictional seed data only)
bash supabase/scripts/start_local.sh
bash supabase/scripts/configure_mobile_local.sh   # writes mobile/.env.development.local

# 2. App
cd mobile
npm install
npx expo run:ios                      # simulator build + Metro
npx expo run:android                  # emulator build; run supabase/scripts/connect_android_emulator.sh first
```

In development builds pointed at the local stack, the sign-in screen offers one-tap sign-in as the seeded users (`mock`, `alex`, `sam`). Email codes from the local stack arrive in Mailpit at http://127.0.0.1:54324.

Checks:

```bash
npm run typecheck
npm test          # vitest: domain, merge rules, legacy handoff
npx prettier --check "src/**/*.{ts,tsx}"
```

`npm run gen:types` regenerates `src/lib/database.types.ts` from the local database.

## Configuration

Builds read `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `EXPO_PUBLIC_TURNSTILE_SITE_KEY` and `EXPO_PUBLIC_EMAIL_CODE_LENGTH` at bundle time. Development builds take them from `.env.development.local`; release builds from `.env.production.local` or the EAS `production` environment. Nothing falls back to a hosted project: a build without them shows a configuration error.

## Releasing

`eas.json` has `development`, `preview` and `production` profiles. Before the first store build:

- Set the production variables in EAS (`eas env:create --environment production ...`), using the same values the Swift app ships with.
- iOS: bump `version`/`buildNumber` in `app.config.ts` above the live 1.3.0 (16).
- Android: create the Play listing and upload key, then publish `site/.well-known/assetlinks.json` with the signing certificate's SHA-256 so invite links open the app.
- Push notifications reach iOS only. The server sends through APNs and stores APNs tokens; Android delivery needs an FCM sender on the server, which is a separate, approved backend change.

## Upgrading from the Swift app

`data/legacy/` reads what the Swift app left on the phone (its Keychain session and any unsynced SwiftData rows and receipt photos) on first launch, so an upgrade keeps the user signed in and loses nothing. See `data/legacy/README.md`.
