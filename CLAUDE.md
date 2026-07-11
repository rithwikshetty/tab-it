# CLAUDE.md — tab

Project guidance for Claude Code. Read this before changing anything.

## What tab is

A Splitwise replacement for tracking expenses on group trips. Headed for a public App Store release; no monetisation, no ads. iOS-first (iOS 18+). App Store name: tab-it; domain: tab-it.app. The "pre-launch, no real users" database conventions below hold until launch, then flip to compatibility-preserving migrations.

Pain points being solved: Splitwise's paywall, ads, and aggressive upsells.

## Architecture at a glance

```
tab/
├── design/
│   ├── mockups/                ← Main app screen mockups (v1, v2, …). Sage palette source of truth.
│   ├── expense-entry/          ← Expense entry flow mockups.
│   └── logo/                   ← Logo and app icon assets.
├── Packages/
│   └── TabCore/               ← Swift Package — pure-logic modules, fully unit-tested.
│       ├── Package.swift
│       ├── Sources/TabCore/
│       │   ├── Money.swift
│       │   ├── SplitType.swift
│       │   ├── Models.swift
│       │   ├── SplitCalculator.swift     ← Pure: expense splitting (equal, exact).
│       │   ├── BalanceEngine.swift       ← Pure: per-currency pairwise balances.
│       │   ├── DebtSimplifier.swift      ← Pure: derived trip-wide repayments.
│       │   ├── TripStateDeriver.swift    ← Pure: active vs completed derivation.
│       │   └── ConflictResolver.swift    ← Pure: LWW with delete-wins + writeID tiebreaker.
│       └── Tests/TabCoreTests/
└── supabase/                   ← Postgres schema + RLS + DB tests.
    ├── migrations/
    └── tests/
```

The iOS app target will be added later under `Apps/` (or root) and depends on `TabCore` via local SwiftPM. Supabase hosts auth + realtime + storage + edge functions; the app is offline-first with sync.

## Tech stack — locked

- **iOS 18+**, SwiftUI, SwiftData, Observation, Swift 6 strict concurrency.
- **Swift Testing** (`@Test`, `#expect`, `@Suite`) — not XCTest.
- **Supabase** (Postgres 17.6) for auth (Apple Sign-In + email magic link), realtime, storage, edge functions.
- **Decimal** for all money math. **Never Double.**
- **Multi-currency, no FX conversion** — per-currency pairwise balances only.
- **Last-write-wins** conflict resolution with delete-wins + UUID `writeID` tiebreaker on identical timestamps.
- **Soft delete** on mutable user-visible records (`deleted_at`); 30-day window before hard purge.
- **Email pre-add** trip joining with automatic claim on sign-in.
- **Realtime** on the currently-viewed trip only.

## Conventions

- **Pure-logic modules go in `TabCore`** with no UIKit/SwiftUI/Foundation-app imports beyond what's strictly needed. Everything in `TabCore` is `Sendable`. Pure modules are `enum` (not `struct`) to make instantiation impossible.
- **Balance computation uses canonical pair-key** (sorted UUIDs, lo/hi): positive amount means `hi` owes `lo`. Always emit both mirrored `UserBalance` rows when surfacing to callers.
- **Simplified debts** are derived per trip and currency from net member positions. Pair balances remain the source of truth; simplification never rewrites expense, split, payment, or settlement history.
- **Equal-split remainders** distribute 1 cent at a time to participants with lexicographically lowest UUIDs (deterministic, not random).
- **Exact-split** validates: sum matches total, no missing participants, no extras. Throws on mismatch.
- **No `XCTest`.** All tests are Swift Testing (`import Testing`).
- **Tests live in `Tests/<TargetName>Tests/`** — canonical SPM layout.
- **`.build/` and `.swiftpm/` are gitignored** — never commit them.
- **Keep a live working log in `docs/working_log/`** while executing actual repo work. Name files `YYYY-MM-DD-descriptive-slug.md`. The log is **chronological and append-only**: start with the goal, then append each meaningful update (findings, direction changes, blockers, pivots, decisions, validations) as a new timestamped entry. Never rewrite or remove earlier entries — the point is a full narrative of how the work unfolded, including dead ends and changes in direction.

## Database

- Pre-launch default: there are no real users. Prefer destructive schema evolution and full DB recreation/reset over compatibility-preserving migration chains.
- Unless the user explicitly asks to preserve existing data, agents may drop and recreate tables, policies, functions, triggers, and related DB objects.
- Dummy/seed data is disposable. Recreate and reseed freely when validating features.
- Editable database SQL lives in numbered files under `supabase/sql/`. `supabase/schema.sql` is only a small source map.
- After editing `supabase/sql/*.sql`, run `./supabase/scripts/build_schema.sh --write` and `bash supabase/tests/00_sql_assembly.sh` so the generated baseline stays in sync.
- Migration strategy is baseline-first: rewrite/squash `supabase/migrations/20260518000000_baseline.sql` via the build script; do not create incremental migration chains unless the user explicitly asks.
- For agents with Supabase MCP access, use MCP for remote destructive DB work. Prefer `apply_migration` with the current baseline/destructive SQL; use `reset_branch` for disposable Supabase development branches.
- CLI fallback/human reset command: `./supabase/scripts/recreate_db.sh` (builds the schema from `supabase/sql/*.sql`, then applies `destructive_teardown.sql` + the generated schema via `supabase db query` against the linked DB or `SUPABASE_DB_URL`).
- Run the pgTAP suites with `./supabase/scripts/run_db_tests.sh` (every `supabase/tests/[0-9]*.sql` against the linked DB; each is transactional and rolls back).
- Receipt storage objects/buckets cannot be deleted with raw SQL. Use `./supabase/scripts/clear_receipts_storage.sh`; pass `SUPABASE_SERVICE_ROLE_KEY` and `--delete-bucket` to delete the bucket itself.
- Remote DB resets do not clear local SwiftData. If stale trips still appear in the app, uninstall the app from the simulator/device or reset simulator content.
- DB tests live in `supabase/tests/` as pgTAP `.sql` files.
- **RLS is mandatory** on every public table. Every test must verify both the allow and deny path.
- Mutable synced row-tables use `updated_at` + `write_id` (UUID), plus `deleted_at` where the row is soft-deleted.
- Direct `trip_people` insert is forbidden for clients. Trip creation goes through `create_trip_with_self`; adding people goes through `add_trip_person_by_email`; sign-in claims go through `claim_trip_people_for_current_email`.
- Expense + split writes must be transactional; the DB enforces split totals and trip-person references for payers, participants, settlements, categories, and mute prefs.
- Trip access derives from joined `trip_people` rows — RLS policies all read from it.
- Default remote apply path for agents is Supabase MCP. Use `./supabase/scripts/recreate_db.sh` when MCP is unavailable or when a human wants a terminal command.

## Design mockups

Mockups live in `design/` organised by feature area, one subfolder per area:

| Subfolder        | Contents                              |
|------------------|---------------------------------------|
| `mockups/`       | Main app screens and flows            |
| `expense-entry/` | Expense entry UI and flow iterations  |
| `logo/`          | Logo explorations, app icon assets    |

**Naming:** each iteration is `v{N}.html` (`v1.html`, `v2.html`, …). Increment from the highest existing version in that subfolder. Never overwrite or rename a previous iteration — old versions are kept for reference.

**New feature areas** get a new kebab-case subfolder under `design/` (e.g., `design/settings/`).

**Non-HTML assets** (SVG, PNG) use descriptive kebab-case names in the relevant subfolder (e.g., `logo/app-icon.svg`).

**Sage palette** in `design/mockups/v1.html` is the locked source of truth for design tokens.

## What NOT to do

- **No Android.** iOS-only.
- **No Double for money.** Decimal only. If you see a `Double` near money, fix it.
- **No `XCTest` migrations.** Stay on Swift Testing.
- **No mocking SwiftData or Supabase in unit tests.** TabCore is pure — it doesn't need mocks. Integration tests use real Supabase (separate test schema or branch).
- **No backwards-compat shims, no feature flags for in-flight work, no deprecated/legacy aliases.** Change the code; we have no prod users yet.
- **No emojis in code or commits** unless the user explicitly asked for them. (Emojis in mockup HTMLs are intentional — categories.)

## Running things

```bash
# Swift tests
cd Packages/TabCore && swift test

# Open mockups (main app screens)
open design/mockups/v1.html

# Supabase — verify split SQL, then destructive reset/recreate
bash supabase/tests/00_sql_assembly.sh
./supabase/scripts/recreate_db.sh
```

### Developer mode (mock auth)

The simulator cannot do Apple Sign-In. To bypass auth and sign in as a mock user (`Test User`, `mock@tab.local`), launch with `TAB_MOCK_AUTH=1`:

```bash
# Via simctl (after building)
SIMCTL_CHILD_TAB_MOCK_AUTH=1 xcrun simctl launch <SIMULATOR_UDID> <BUNDLE_ID>

# Via XcodeBuildMCP session defaults
session_set_defaults with env: {"TAB_MOCK_AUTH": "1"}
```

**Always use mock auth when testing the app in the simulator.** The mock user ID is `11111111-1111-1111-1111-111111111111`. Set `TAB_REAL_AUTH=1` to force real auth even in debug builds.

## Where to find things

- **Design tokens (Sage palette)** → `design/mockups/v1.html` — Sage hex values are the locked source of truth; port them to the Asset Catalog when scaffolding the app.
- **Supabase project ref** → set locally with `SUPABASE_PROJECT_REF`; no public default is checked in.
- **MCP servers** → `.mcp.json` (Supabase MCP is HTTP-typed).
