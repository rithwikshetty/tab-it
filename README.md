# tab

tab (tab-it.app) is an expense tracker for group trips: a small Splitwise-style app for expenses, balances, settlements, receipt photos and offline-first sync, with no ads or paywall.

## Stack

- One Expo / React Native app for iOS and Android in `mobile/` (TypeScript, Expo Router)
- Pure money, splitting and balance logic in `mobile/src/domain`, tested with vitest
- Supabase Postgres, Auth, Realtime, Storage and Edge Functions for the backend (`supabase/`)

## Getting started

```bash
bash supabase/scripts/start_local.sh            # local Supabase in Docker, fictional seed data
bash supabase/scripts/configure_mobile_local.sh # points development builds at it

cd mobile
npm install
npx expo run:ios       # or: npx expo run:android
```

`mobile/README.md` covers the app's structure, data flow, checks and releasing. `CLAUDE.md` holds the project rules, including the production-safety rules for the database.

## Tests

```bash
cd mobile && npm run typecheck && npm test
bash supabase/tests/00_sql_assembly.sh
```

## License

MIT. See `LICENSE`.
