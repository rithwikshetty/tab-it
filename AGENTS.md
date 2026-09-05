# AGENTS.md — tab

Guidance for AI coding agents (Codex, Cursor, Copilot Workspace, etc.) working in this repo.

This file mirrors [`CLAUDE.md`](CLAUDE.md) — both are kept in sync. If they diverge, `CLAUDE.md` is authoritative.

---

## What tab is

A Splitwise replacement for tracking expenses on group trips. Private friend-group use, no monetisation. The iOS app is live and Supabase production contains real user data. Android is planned as a phased native client; itinerary and cross-trip spend analytics remain out of scope.

## Architecture at a glance

```
tab/
├── Apps/
│   ├── Tab/                    ← Existing iOS app.
│   └── TabAndroid/             ← Native Kotlin/Compose Android Gradle build.
├── design/
│   ├── mockups/                ← Main app screen mockups (v1, v2, …). Sage palette source of truth.
│   ├── expense-entry/          ← Expense entry flow mockups.
│   └── logo/                   ← Logo and app icon assets.
├── Packages/TabCore/          ← Swift Package — pure-logic modules.
│   ├── Sources/TabCore/       ← Money, SplitType, Models, SplitCalculator, BalanceEngine,
│   │                              DebtSimplifier, TripStateDeriver, ConflictResolver.
│   └── Tests/TabCoreTests/    ← Swift Testing (@Test/#expect), including shared Android parity fixtures.
└── supabase/                   ← Postgres schema + RLS + DB tests.
    ├── migrations/
    └── tests/
```

The iOS app depends on `TabCore` via local SwiftPM. The independent Android build lives at `Apps/TabAndroid` with `:app`, pure Kotlin `:core:domain`, and Android-only Room `:core:data` modules. Supabase hosts auth + realtime + storage + edge functions; clients are offline-first.

## Tech stack — locked

| Layer       | Choice                                                         |
|-------------|----------------------------------------------------------------|
| Platform    | iOS 18+, Swift 6 strict concurrency                            |
| UI          | SwiftUI + Observation framework                                |
| Persistence | SwiftData (client), Postgres 17.6 via Supabase (server)        |
| Tests       | Swift Testing (`@Test`, `#expect`), pgTAP for DB               |
| Money       | `Decimal` only — never `Double`                                |
| Currency    | Multi-currency, no FX conversion (per-currency balances)       |
| Sync        | Last-write-wins + delete-wins + UUID write-id tiebreaker       |
| Soft delete | `deleted_at` on mutable user-visible records; 30-day purge window |
| Auth        | Apple Sign-In primary + email magic link fallback              |
| Joining     | Email pre-add + automatic claim on sign-in                     |
| Realtime    | Currently-viewed trip only                                     |

## Conventions

- **Pure-logic modules** live in `TabCore` as `enum` (uninstantiable) with `Sendable` types.
- **Balance pair-key**: sort UUIDs `(lo, hi)`; positive amount means `hi` owes `lo`. Surface both mirrored `UserBalance` rows externally.
- **Simplified debts**: derive per-trip, per-currency repayment suggestions from net member positions. Keep pair balances as the source of truth; never rewrite expense, split, payment, or settlement history to simplify debts.
- **Equal-split remainder**: distribute 1¢ at a time to participants with lexicographically lowest UUIDs. Deterministic.
- **Exact-split**: validates sum, no missing/extra participants. Throws on mismatch.
- **Tests live in `Tests/<TargetName>Tests/`** (canonical SPM).
- **`.build/` and `.swiftpm/` are gitignored.**
- **Keep a live working log in `docs/working_log/`** for substantial implementation or investigation. Small isolated edits do not need a new log. Name files `YYYY-MM-DD-descriptive-slug.md`. The log is **chronological and append-only**: start with the goal, then append each meaningful update (findings, direction changes, blockers, pivots, decisions, validations) as a new timestamped entry. Never rewrite or remove earlier entries — the point is a full narrative of how the work unfolded, including dead ends and changes in direction.
- **Use GitHub Issues as the main work tracker.** Use an existing bounded issue for a phase or substantial deliverable; create one when issue updates are authorized. Small maintenance edits do not require a new issue. Add concise comments at meaningful milestones: start, material decision or blocker, validation, and completion. Link the relevant report, pull request, or commit; do not paste raw logs or secrets into issues.
- **Explain substantial phase plans and outcomes with concise HTML reports in `docs/reports/`.** Routine edits need only a concise response. Name reports `YYYY-MM-DD-descriptive-slug.html`. Prefer one living report per initiative, updated as phases progress. Reports must be self-contained, readable on mobile and desktop, visually use the established sage palette, and state the outcome, scope, decisions, risks, current phase, evidence, and next action without repeating the same information in multiple sections.

## Database

- **Production contains real users and must be preserved.** Treat production Supabase, Auth, Storage, Realtime, Edge Functions, and user data as read-only by default.
- Never reset, recreate, drop, truncate, reseed, or bulk-delete production data or schema objects. The repository intentionally provides no database-recreation command.
- Do not run Supabase CLI, MCP, SQL, migrations, Storage cleanup, Auth changes, or remote tests against production unless the user explicitly authorizes that exact operation in the current task and the exact project target has been verified first.
- Development and automated tests must use mocks, a local Supabase stack, or an explicitly isolated non-production project/branch. Debug builds must never silently fall back to production configuration.
- The deployed baseline migration is immutable. Do not rewrite or squash an applied migration. Any future database change requires a forward-only, compatibility-preserving migration designed for existing users, tested locally and in an isolated environment, with backup, rollback, and production approval documented before deployment.
- Editable database SQL currently lives in numbered files under `supabase/sql/`, with `supabase/schema.sql` as a source map. Do not edit SQL, migrations, RLS, functions, Auth, Realtime, or Storage configuration until a production-safe migration plan for the specific change is approved.
- `bash supabase/tests/00_sql_assembly.sh` is a local static source-consistency check and does not connect to a database. pgTAP tests in `supabase/tests/` may run only against an isolated non-production target.
- RLS mandatory on every public table; tests must verify both allow and deny.
- Sync columns on mutable synced row-tables: `updated_at` (timestamptz), `write_id` (uuid), plus `deleted_at` where the row is soft-deleted.
- Trip access derives from joined `trip_people` rows — direct person insert is forbidden; email adds and sign-in claims go through RPCs.
- Expense + split writes must be transactional; the DB enforces split totals and trip-person references.

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

## Don't do these

- Don't add features outside the current scope: itinerary, cross-trip spend analytics, %/shares splits, payment-app links, or currency conversion. Android work must follow the approved phased plan and its GitHub issue.
- No `Double` for money — only `Decimal`.
- No XCTest — Swift Testing only.
- No mocking SwiftData or Supabase in unit tests. TabCore is pure; it doesn't need mocks.
- Do not break persisted data, deployed contracts, authentication identities, or older installed clients. Production changes require an explicit compatibility and rollout plan.
- No emojis in code or commits unless the user explicitly asked.

## Running things

```bash
cd Packages/TabCore && swift test     # Swift tests
cd Apps/TabAndroid && ./gradlew test lint # Android JVM tests + lint
open design/mockups/v1.html            # Mockups (main app screens)
bash supabase/tests/00_sql_assembly.sh # Static SQL source assembly check only
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

## Pointers

- **Design tokens** → `design/mockups/v1.html` (Sage palette is locked)
- **Plans and phase reports** → `docs/reports/`
- **Work tracking** → GitHub Issues in `rithwikshetty/tab-it`
- **Local Supabase** → `supabase/config.toml` uses project id `tab-local`; local scripts refuse `SUPABASE_PROJECT_REF`
- **MCP config** → `.mcp.json` (Claude Code), `.codex/config.toml` (Codex), `.pi/mcp.json` (Pi)

## Task completion

Continue an authorized change through implementation, affected checks, and fixes for failures it causes. Choose routine reversible details from the established architecture. Ask only for missing facts or decisions that materially change the result. The production and migration boundaries above remain in force.

Select validation by changed behavior: TabCore for shared money logic, the affected Android modules for Android work, and isolated database checks for SQL changes. Documentation-only edits need content, links, and diff checks. Do not rerun passing suites without a change or unresolved concern. Browser and simulator interaction require an explicit request for this task.
