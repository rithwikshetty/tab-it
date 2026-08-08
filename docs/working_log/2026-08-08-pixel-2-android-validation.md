# Pixel 2 Android validation and Git publication

## 2026-08-08 14:13 BST — Goal

Validate the existing native Android client on the connected Google Pixel 2, preserve the production-isolation boundary, record fresh evidence against the current local commit, and publish all verified local commits to `origin/main` only after the device and repository checks pass.

## 2026-08-08 14:13 BST — Repository and tracker audit

The worktree is clean on `main` at `c8a7db1` and, after fetching `origin`, is twelve commits ahead and zero commits behind `origin/main`. The unpublished range is the previously completed Android foundation and Phases 1–8 tracked by GitHub issues #33–#42. Issue #42 and the living Android report both state that the final implementation was validated locally but not pushed or deployed. `git diff --check origin/main..HEAD` passes, and there are no staged or unstaged changes.

## 2026-08-08 14:13 BST — Physical-device preflight

ADB identifies one authorized physical device: Google Pixel 2 (`walleye`) running Android 11 / API 30. The device is connected through ADB's libusb backend because Platform Tools 37.0.1's native macOS USB backend opened the device and then failed reads; the alternate backend has remained stable across repeated shell probes. Java 17 and the Android SDK are present at the paths documented by `Apps/TabAndroid/README.md`, so validation will use those scoped environment variables without altering the machine's global Java configuration.

## 2026-08-08 14:18 BST — Fresh build and initial connected-test dead end

The documented Android checks pass at the current commit. A forced `./gradlew test lint assembleDebug --rerun-tasks` executed all 153 tasks successfully. The first combined connected-test command incorrectly applied an app-class filter to both the app and Room modules, so the Room runner could not find app-only test classes. After separating the invocations, all 13 Room tests passed on the Pixel.

The three focused Compose tests initially reached their test methods but reported no Compose hierarchy. Device inspection showed the Pixel was dozing with its keyguard showing. This was a physical test-host condition rather than an application or Android 11 compatibility failure.

## 2026-08-08 14:22 BST — Pixel UI validation and app launch

After waking the Pixel and dismissing its non-secure keyguard, the same three Compose tests passed unchanged: expense entry exact-decimal validation, settlement suggestion entry, and Splitwise import preview. The freshly rebuilt `0.1.0-debug` APK then installed successfully, launched as the resumed foreground activity, exposed a live window and process, and produced no `AndroidRuntime` crash. A read-only screenshot confirmed the sage-themed local-development sign-in screen rendered correctly at the Pixel 2's 1080 × 1920 resolution.

The physical-device scope remained production-safe: no hosted Supabase endpoint, production credential, production database, Auth, Storage, Realtime, Edge Function, migration, or deployment was accessed. Full backend integration remains covered by the previously recorded disposable local-Supabase emulator run; this Pixel pass covered Room, focused Compose behavior, installation, launch, rendering, and crash absence without redirecting the physical device to any backend.

## 2026-08-08 14:24 BST — Documentation and publication gate

Updated the existing living Android report rather than creating a competing initiative report. The report now distinguishes the original complete emulator/local-Supabase evidence from the new Android 11 Pixel pass and keeps broader device coverage plus hosted release readiness separate. The cached project validator reports the HTML valid, `git diff --check` passes, and the publish range contains no tracked `local.properties`, environment file, build output, keystore, or signing file.
