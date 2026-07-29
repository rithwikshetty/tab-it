# tab Android

Native Android client for tab. This is an independent Gradle build inside the
same repository as the existing iOS app.

## Toolchain

- JDK 17
- Android Gradle Plugin 9.3.0
- Gradle Wrapper 9.5.0
- Kotlin 2.4.10
- Compose BOM 2026.06.00
- compile SDK 37, target SDK 36, minimum SDK 26

On the current Homebrew-based macOS setup:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

## Checks

```bash
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

The checked-in debug backend is `http://10.0.2.2:54321`, Android Emulator's
alias for the host machine's local Supabase API. Release builds contain no
backend URL. Runtime validation refuses hosted Supabase URLs; there is no
production fallback.

Use the `Tab_API_36` Android 16 emulator for local device tests.
