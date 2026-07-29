# Repository architecture for adding Android to tab

Research date: 2026-07-29.

Question: should tab reorganize its repository before adding a full native
Android app, and should the iOS and Android clients live in one repository or
separate repositories?

This note uses primary sources: Android and Gradle documentation, Apple's Swift
Package documentation, Kotlin Multiplatform documentation, Supabase
documentation, and Google's official Now in Android repository. It did not
connect to, inspect, query, or modify any Supabase project or database. No
Supabase CLI or MCP command was run.

## Short answer

Keep one Git repository, but keep two independent native application builds:

- the existing SwiftUI iOS app and Swift package;
- a new Kotlin/Jetpack Compose Android app with its own Gradle build;
- the existing Supabase source, design references, product documentation, and
  cross-platform behavior fixtures shared at repository level.

Do **not** reorganize the working iOS tree just to make the names symmetrical.
The current top-level separation is already useful:
[`Apps/Tab`](../../Apps/Tab), [`Packages/TabCore`](../../Packages/TabCore), and
[`supabase`](../../supabase). The least risky change is to add
`Apps/TabAndroid` when Android implementation begins.

Planning should come before structural churn. First write down the platform
decision, feature-parity definition, backend safety boundary, and initial
vertical slice. Then create only the directories needed by the first compiling
Android code and its tests. Empty future-facing module trees tend to encode
guesses before the real dependency boundaries are known.

## 2026-07-29 verification: is this the standard Android stack?

Yes. A fresh check of Google's current first-party Android guidance supports
the proposed Kotlin, Jetpack Compose, and Gradle stack:

- **Kotlin is the recommended starting language for a new Android app.**
  Android describes its tooling, libraries, samples, documentation, and
  training as Kotlin-first and explicitly recommends starting a new app with
  Kotlin. Java remains supported, so Kotlin-first does not mean Java is
  obsolete
  ([Android's Kotlin-first approach](https://developer.android.com/kotlin/first),
  [Kotlin and Android](https://developer.android.com/kotlin/)).
- **Jetpack Compose is the standard modern choice for a new native Android
  interface.** Android calls Compose its recommended modern toolkit for native
  UI and strongly recommends it for new apps across phones, tablets, foldables,
  and Wear OS. Compose project templates use Kotlin because Compose is
  Kotlin-based
  ([Jetpack Compose](https://developer.android.com/compose),
  [Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations),
  [Compose quick start](https://developer.android.com/develop/ui/compose/setup)).
- **Gradle with the Android Gradle Plugin is the normal first-party build
  path.** Android's build documentation says Android applications are typically
  built with Gradle; the Android Gradle Plugin supplies the Android-specific
  tasks, while the checked-in Gradle Wrapper makes builds repeatable
  ([Gradle build overview](https://developer.android.com/build/gradle-build-overview),
  [configure an Android build](https://developer.android.com/build)).
- **Android Studio is the official, fully supported development environment.**
  Android recommends it for the best Compose experience, including project
  templates, previews, debugging, and Gradle integration
  ([Compose quick start](https://developer.android.com/develop/ui/compose/setup),
  [Android Studio templates](https://developer.android.com/studio/projects/templates)).

The phrase **native Android app** needs one qualification. Compose is Google's
native Android UI toolkit, so Kotlin plus Compose is unequivocally a mainstream
native stack. Google does not require every company to choose native over
Flutter, React Native, or Kotlin Multiplatform; that remains a product and team
decision. For tab, a separate native Android client is the conservative choice
because the existing iOS app is already native, the goal is full platform
functionality, and it avoids rewriting a working production app merely to
introduce shared runtime code.

Therefore the recommendation is confirmed, not experimental:
**Kotlin + Jetpack Compose + Gradle/Android Gradle Plugin in
`Apps/TabAndroid`**. Room, WorkManager, repositories, and coroutines remain the
appropriate Jetpack architecture building blocks described later in this note.
Exact library and plugin versions should be selected when Phase 1 starts, so
the skeleton uses mutually compatible current stable releases rather than
version numbers frozen in this planning document.

## 2026-07-29 Phase 1 toolchain

Phase 1 selected the following mutually compatible versions from current
first-party release documentation:

| Component | Version | Reason |
|---|---:|---|
| JDK | 17.0.20 | AGP 9.3 requires and defaults to JDK 17. |
| Android Gradle Plugin | 9.3.0 | Current stable release; supports API 37. |
| Gradle Wrapper | 9.5.0 | Required and default Gradle version for AGP 9.3. |
| Kotlin | 2.4.10 | Current supported Kotlin 2.4 bug-fix release; AGP 9.1+ supports Kotlin 2.4. |
| Compose BOM | 2026.06.00 | Current stable Compose compatibility set. |
| Compile SDK | 37 | Required by current Compose 1.12 libraries. |
| Target SDK | 36 | Current stable Google Play target requirement without opting into Android 17 preview runtime behaviour. |
| Emulator | Android 16 / API 36 ARM64 | Stable runtime matching the target SDK and Apple Silicon host. |

AGP 9's built-in Kotlin support is used for Android modules; the pure JVM
domain module uses the pinned Kotlin plugin directly. The Compose compiler
plugin matches Kotlin 2.4.10. Sources:
[AGP 9.3 release and compatibility](https://developer.android.com/build/releases/agp-9-3-0-release-notes),
[Kotlin releases](https://kotlinlang.org/docs/releases.html),
[Kotlin/AGP compatibility](https://developer.android.com/build/kotlin-support),
[Compose setup](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler),
[Google Play target requirement](https://developer.android.com/google/play/requirements/target-sdk).

## What “same repository” does and does not mean

A Git repository boundary and a build-system boundary are different decisions.
One repository can contain:

- an Xcode/XcodeGen project under `Apps/Tab`;
- a Swift Package Manager build under `Packages/TabCore`;
- an independent Gradle build under `Apps/TabAndroid`;
- the versioned Supabase source under `supabase`.

The Android app does not need to become part of the Xcode build, and the iOS app
does not need to become part of the Gradle build. This is a small polyglot
monorepo: related products are versioned together, while each toolchain remains
independently buildable.

Gradle explicitly supports a build root with multiple focused subprojects,
declared in `settings.gradle.kts`; each subproject has its own build file and
dependencies. Gradle calls this a multi-project build and notes that related
components can be built and tested together while remaining logically isolated
([Gradle multi-project builds](https://docs.gradle.org/current/userguide/multi_project_builds.html)).
That Gradle build can live below the Git root; nothing requires Gradle to own
the entire repository.

Likewise, Apple's Swift Package guidance treats packages as lightweight,
reusable components that can be developed alongside an app. It uses the
conventional `Sources/<Target>` and `Tests/<TargetTests>` layout already used by
TabCore
([Apple: Swift packages](https://developer.apple.com/documentation/Xcode/swift-packages),
[Apple: creating a standalone Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode)).
There is no platform requirement to move that package because an Android
project is added elsewhere in the same Git repository.

## One repository versus separate repositories

There is no Android, Apple, Kotlin, Gradle, or Supabase rule that decides the Git
repository boundary. Official guidance deals mainly with module boundaries
inside a build. Repository choice is an engineering and team-ownership
decision.

| Concern | One repository | Separate repositories |
|---|---|---|
| Backend contract changes | Android, iOS, SQL/RPC source, fixtures, and docs can change in one reviewed commit or pull request | Cross-repository coordination and version tracking are required |
| Platform parity | A single parity matrix and cross-platform fixtures are naturally visible to both clients | Shared behavior tends to be copied or published as a separate artifact |
| CI | Path-filtered iOS, Android, Swift-package, and SQL jobs need to be configured | Each repository has simpler platform-only CI |
| Permissions | Everyone with repository access sees both clients and backend source | Useful when platform teams or vendors need different access |
| Release cadence | Apps can still release independently; Git co-location does not force simultaneous releases | Independent releases are obvious by construction |
| Maintenance | One issue tracker, documentation tree, and source of truth | More repositories, dependency updates, and synchronized changes to manage |

For tab, one repository is the better default because it is one private
product, has one shared backend contract, and does not currently have separate
platform teams or access-control requirements. Separate repositories become
worth considering if Android is handed to an independent vendor/team, repository
permissions must differ, or the clients acquire genuinely independent product
roadmaps. Those conditions are not present merely because the build tools are
different.

Google's official Now in Android sample is useful evidence for the Android side,
not a template to copy wholesale. It keeps the app, `core`, `feature`, `sync`,
build logic, tests, and documentation together in one repository
([android/nowinandroid](https://github.com/android/nowinandroid)). It is also much
larger and more heavily modularized than tab should be on day one.

## Recommended conservative layout

The proposed target shape is:

```text
tab/
├── Apps/
│   ├── Tab/                         # Existing iOS app; leave in place
│   └── TabAndroid/                  # New independent Gradle build root
│       ├── settings.gradle.kts
│       ├── build.gradle.kts
│       ├── gradle/
│       ├── gradlew
│       ├── gradlew.bat
│       ├── app/                     # Android entry point, UI, app wiring
│       └── core/
│           └── domain/              # Pure Kotlin money and ledger rules
├── Packages/
│   └── TabCore/                     # Existing pure Swift domain logic
├── contracts/                       # Add when the first fixture exists
│   ├── domain/                      # Shared JSON inputs/expected outputs
│   └── sync/                        # Conflict/serialization fixtures
├── supabase/                        # One backend source of truth
├── design/                          # Shared visual/product reference
└── docs/                            # ADRs, plans, research, parity matrix
```

`Apps/TabAndroid` should be the Android Studio project root. Initially, keep the
Gradle graph small:

- `:app` for the Android application, Compose UI, repositories, local/remote
  adapters, and sync orchestration;
- `:core:domain` for pure Kotlin calculations and conflict rules that can run
  in fast JVM unit tests without Android dependencies.

Within `:app`, ordinary packages such as `data/local`, `data/remote`,
`data/sync`, and `ui` are enough at first. Extract `:core:database`,
`:core:network`, `:core:data`, `:core:sync`, or `:feature:*` Gradle modules only
when code size, ownership, build time, or dependency boundaries make the
benefit concrete.

This deliberately follows Android's guidance rather than copying the maximum
module count from a showcase app. Android recommends clear UI and data layers,
repositories between UI and data sources, coroutines/flows, and an optional
domain layer when business logic is reused or complex
([Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations)).
Its modularization guide says modules should be cohesive and loosely coupled,
but specifically warns that too-fine granularity adds build complexity and
boilerplate, and that small apps can keep layers in packages
([Android modularization guide](https://developer.android.com/topic/modularization),
[common modularization patterns](https://developer.android.com/topic/modularization/patterns)).

### What not to move now

Do not rename `Apps/Tab` to `Apps/TabIOS` solely for visual symmetry. That would
touch XcodeGen paths, documentation, scripts, and developer habits without
improving Android delivery.

Do not move `Packages/TabCore` into the Android tree. It remains the native iOS
logic package.

Do not duplicate `supabase` into each app. The SQL, functions, and backend
contract must have one versioned source of truth, even though each client has
its own data-transfer types and adapters.

Do not create every possible Android feature module in advance. Add a module
when it establishes a real dependency boundary, not because a sample app has
one.

## Native Android versus Kotlin Multiplatform

Kotlin Multiplatform (KMP) is a valid industry option, but it is not a
prerequisite for keeping both apps in one repository. JetBrains documents three
gradual choices: share a small piece of logic, share business logic while
keeping native UI, or share UI as well. Common business logic can live in a
shared source set, with platform-specific APIs supplied separately
([Kotlin: share code on platforms](https://kotlinlang.org/docs/multiplatform/multiplatform-share-on-platforms.html),
[Kotlin: Android and iOS approaches](https://kotlinlang.org/docs/multiplatform/build-ios-android-app.html)).

For tab, the conservative starting point is:

1. retain SwiftUI and SwiftData on iOS;
2. use Kotlin, Compose, and Room on Android;
3. port the pure TabCore behavior to `:core:domain`;
4. run both implementations against the same platform-neutral JSON fixtures.

This avoids making the existing iOS app consume a Kotlin/Native framework
before Android has proven value. It also preserves a later KMP path: if
maintaining two domain implementations becomes a demonstrated burden, the
isolated Kotlin domain module can be evaluated for conversion into a KMP shared
module. JetBrains explicitly supports incremental adoption of one module or
layer rather than requiring a rewrite
([Kotlin: integrate into an existing app](https://kotlinlang.org/docs/multiplatform/multiplatform-integrate-in-existing-app.html)).

The decision should be revisited with evidence after the first end-to-end
Android slice, not made from a desire to maximize code sharing before either
client boundary is understood.

## Android application architecture

The Android client should use the same product rules and backend contract as
iOS, but use Android-native persistence and lifecycle tools:

```text
Compose UI
    ↓ events / ↑ immutable UI state
ViewModel
    ↓
Repository
    ├── Room local source of truth
    └── Supabase remote adapter
             ↕
       sync/outbox worker
```

Android's offline-first guidance says repositories with network access should
have local and network data sources, and that the local data source should be
the exclusive source read by higher layers. It describes Room-backed queues
and WorkManager for persistent synchronization and retry
([Android offline-first guide](https://developer.android.com/topic/architecture/data-layer/offline-first)).
Google's Now in Android sample implements the same broad pattern: repositories
read from local storage, remote results are written locally, and WorkManager
handles synchronization/backoff
([Now in Android architecture](https://github.com/android/nowinandroid/blob/main/docs/ArchitectureLearningJourney.md)).

Supabase's Kotlin quickstart shows the Android dependency setup, while its
reference states that the Kotlin library supports Auth, PostgREST, Realtime,
Storage, and Functions. The reference also makes an important qualification:
`supabase-kt` is community-maintained rather than an official Supabase client
([Supabase Android Kotlin quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/kotlin),
[Supabase Kotlin introduction](https://supabase.com/docs/reference/kotlin/introduction)).
Therefore, isolate it behind a small Android remote-data adapter instead of
allowing SDK types to spread through ViewModels and domain code.

## Production database safety boundary

Repository preparation and the first Android skeleton require **no database
change** and no connection to production.

The project should adopt these gates before Android integration work:

1. Debug and test builds must not silently default to the production Supabase
   URL. Configuration should fail clearly if an approved local/development
   target is absent.
2. Only a Supabase publishable key may be included in a mobile app. Supabase
   describes mobile binaries as public environments and says secret or
   `service_role` keys must never be bundled in them
   ([Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)).
3. Backend compatibility should first be assessed from the versioned repository
   source. Any required SQL, RPC, Edge Function, Auth, Realtime, Storage, or push
   change must become its own reviewed plan.
4. When backend testing is authorized, use a local stack or isolated
   development/preview environment, not production. Supabase recommends local
   development for safe testing without affecting production, and its branches
   are separate, data-less environments intended for experiments
   ([Supabase local development](https://supabase.com/docs/guides/local-development),
   [Supabase branching](https://supabase.com/docs/guides/deployment/branching)).
5. Production deployment must remain a separate explicit approval after
   migration review, automated tests, and rollback planning.

“No database changes now” should not be confused with “Android can never need a
backend change.” Full parity may expose platform additions such as Android push
delivery or OAuth/deep-link configuration. The correct response is to identify
those gaps in a read-only compatibility audit and schedule them behind the
safety gates above—not to change production while arranging folders.

## Phased setup

### Phase 0 — decisions and inventory; no application or database changes

Produce:

- an architecture decision record for one repository, two native builds, and
  the initial no-KMP choice;
- a feature-parity matrix covering behavior, offline behavior, cross-device
  behavior, and validation—not just screens;
- a production-safety note identifying which configurations can point at which
  environment;
- a read-only backend compatibility inventory of existing tables, RPCs, Auth,
  Realtime, Storage, Edge Functions, push, and deep links.

Exit condition: the first Android vertical slice and its acceptance tests are
specific enough to build.

### Phase 1 — minimal Android build skeleton

Add `Apps/TabAndroid` with the Gradle wrapper, version catalog, `:app`, and
`:core:domain`. Establish Kotlin/Compose compilation, unit tests, lint, and
Android-only CI. Do not add backend credentials or connect to production.

Exit condition: a clean clone can build and test both TabCore and the empty
Android application independently.

### Phase 2 — behavior parity harness

Add the first `contracts/domain` fixtures for money, equal/exact splitting,
UUID ordering, balances, debt simplification, and conflict resolution. Run the
same cases through Swift TabCore and Kotlin `:core:domain`.

The fixture format is the shared contract; Swift and Kotlin remain idiomatic
native implementations.

Exit condition: core calculations produce identical expected results on both
platforms, including decimal rounding and deterministic remainder behavior.

### Phase 3 — one local end-to-end vertical slice

Build only enough app infrastructure for:

1. development authentication;
2. Room-backed trip list;
3. trip detail;
4. creating an equal-split expense while offline;
5. queued synchronization and retry;
6. convergence with another client in an approved non-production environment.

This slice validates the high-risk architecture—identity, local persistence,
atomic remote writes, serialization, conflicts, and retry—before recreating all
screens.

Exit condition: automated tests and a manual acceptance run demonstrate offline
creation and cross-client convergence without production access.

### Phase 4 — feature slices

Add one complete feature at a time: trip/member management, full expense entry,
receipts, balances and settlements, friends/non-group expenses, activity,
import/export, settings/account deletion, then realtime and push. Extract
additional Gradle modules only as the dependency graph earns them.

Exit condition: every parity-matrix row has Android, offline, cross-device, and
test evidence.

### Phase 5 — backend and release readiness

Only after the compatibility inventory identifies required server changes,
design and test those changes in an isolated environment. Review RLS, mobile key
handling, Auth callbacks, push delivery, deep links, migrations, monitoring, and
rollback. Production changes and Play release remain separately approved
actions.

## Recommendation for the next action

Do not start by moving files. The next useful deliverables are the Phase 0 ADR
and parity matrix. Once those settle the first vertical slice, add only
`Apps/TabAndroid/:app` and `Apps/TabAndroid/:core:domain`.

In plain English: keep the whole product together, keep the two apps technically
independent, share specifications and test cases before attempting shared
runtime code, and keep production completely outside the setup phase.
