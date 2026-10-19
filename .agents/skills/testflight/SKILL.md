---
name: testflight
description: Build the tab iOS app from main and upload it to TestFlight, so the user gets it through the TestFlight app. Use when the user asks to ship, release, upload or put a build on TestFlight, or to get the latest main onto their phone.
---

# Ship an iOS build to TestFlight

This uploads a production build of `mobile/` to App Store Connect. The user is the only tester in the internal group "Personal", which has automatic distribution on, so an uploaded build reaches their TestFlight app without review once Apple finishes processing it. Everything below comes from the repo and the Mac, so don't ask the user for identifiers.

Fixed values: bundle `com.rithwikshetty.tab`, Apple team `36VWCMM6GL`, App Store Connect app id `6770451955`, production Supabase ref `gaseuxsieddlksxtdliq`.

## 1. Check what ships

1. Work from the main checkout on `main`, up to date with `origin/main`. The build is whatever is in the working tree, so when `git status` shows uncommitted changes, ask whether they belong in the build before going on.
2. `mobile/.env.production.local` must exist and set `EXPO_PUBLIC_SUPABASE_URL` (the production ref above), `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `EXPO_PUBLIC_TURNSTILE_SITE_KEY`, `EXPO_PUBLIC_EMAIL_CODE_LENGTH` and `EXPO_PUBLIC_GOOGLE_SIGN_IN`. Check the names with `sed 's/=.*//'`; never print the values. If the file is missing, stop and tell the user.
3. From `mobile/`: `npm run typecheck`, `npm test`. Stop on a failure.

## 2. Bump the build number

In `mobile/app.config.ts`, add one to `ios.buildNumber`. App Store Connect rejects a build number it has already seen for this version. Leave `version` alone unless the user asks, or the upload says the version is closed (see below). Commit the bump on its own (`chore(mobile): iOS build <n>`) and push it, so the build matches a commit on main.

## 3. Prebuild and archive

From `mobile/`, in this order. Run the archive in the background, keep its task ID, and wait for its completion notification. It takes about ten minutes.

```sh
NODE_ENV=production npx expo prebuild --platform ios --clean > /tmp/tab-prebuild.log 2>&1

rm -rf /tmp/tab-release/tabit.xcarchive && mkdir -p /tmp/tab-release
NODE_ENV=production xcodebuild -workspace ios/tabit.xcworkspace -scheme tabit \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/tab-release/tabit.xcarchive -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=36VWCMM6GL CODE_SIGN_STYLE=Automatic archive > /tmp/tab-archive.log 2>&1
```

Success is `** ARCHIVE SUCCEEDED **` in the log. On failure, read the first `error:` lines.

`NODE_ENV=production` on the archive is what makes the JavaScript bundle read `.env.production.local`. Prebuild loads `.env.development.local` whatever `NODE_ENV` says, so `app.config.ts` must never depend on an environment variable.

Before uploading, confirm the bundle points at production. The first count must be at least 1 and the second must be 0:

```sh
APP=$(ls -d /tmp/tab-release/tabit.xcarchive/Products/Applications/*.app)
strings "$APP/main.jsbundle" | grep -c gaseuxsieddlksxtdliq
DEV_KEY=$(sed -n 's/^EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=//p' .env.development.local)
[ -n "$DEV_KEY" ] && strings "$APP/main.jsbundle" | grep -cF "$DEV_KEY"
```

Also check `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist"` shows the new build number.

## 4. Upload

```sh
rm -rf /tmp/tab-release/export
xcodebuild -exportArchive -archivePath /tmp/tab-release/tabit.xcarchive \
  -exportOptionsPlist mobile/release/ExportOptions.plist \
  -exportPath /tmp/tab-release/export -allowProvisioningUpdates > /tmp/tab-upload.log 2>&1
```

Run it from the repo root in the background. Success is `Upload succeeded` and `** EXPORT SUCCEEDED **`. Known failures:

- "You do not have required contracts": an agreement in App Store Connect > Business needs accepting. Tell the user. After acceptance it can take up to a day to clear.
- "No Account for Team": Xcode > Settings > Accounts needs an Apple ID on team `36VWCMM6GL`.
- The build number is already used: bump it again (step 2) and archive again.
- The version is closed for new builds, because that version has been approved for the App Store: ask the user for the next version number, set `version` and reset nothing else.

## 5. Hand over

Apple processes the build for 5 to 30 minutes, then TestFlight on the user's phone offers it. Nothing else is needed for the user.

The external group "Family" is other people. Add a build to it only when the user asks in this task. Then use the codex-computer-use skill in the user's Chrome to add the build to "Family" in App Store Connect, fill "What to Test" from the commits since the last Family build, and submit it for Beta App Review. The review notes must say that Sign in with Apple works with any Apple ID. Apple reviews the first build of each version, usually within a day.

Report the version, build number and commit uploaded, and whether Family was asked for.
