import type { ExpoConfig } from "expo/config";

// The bundle identifier, Apple team and URL scheme match the live App Store
// app, so this build installs as an update to it: Sign in with Apple keeps the
// same user identifiers, the Supabase auth redirect allowlist already contains
// `<bundle id>://auth-callback`, and tab-it.app invite links keep resolving.
const BUNDLE_ID = "com.rithwikshetty.tab";
const APPLE_TEAM_ID = "KR8C647GCW";

const config: ExpoConfig = {
  name: "tab-it",
  slug: "tab",
  scheme: BUNDLE_ID,
  version: "2.0.0",
  orientation: "portrait",
  icon: "./assets/icon.png",
  userInterfaceStyle: "light",
  backgroundColor: "#FAF7F0",
  ios: {
    bundleIdentifier: BUNDLE_ID,
    appleTeamId: APPLE_TEAM_ID,
    buildNumber: "17",
    supportsTablet: false,
    usesAppleSignIn: true,
    associatedDomains: ["applinks:tab-it.app"],
    infoPlist: {
      ITSAppUsesNonExemptEncryption: false,
    },
  },
  android: {
    package: BUNDLE_ID,
    versionCode: 1,
    adaptiveIcon: {
      backgroundColor: "#EEF2E7",
      foregroundImage: "./assets/android-icon-foreground.png",
      monochromeImage: "./assets/android-icon-monochrome.png",
    },
    softwareKeyboardLayoutMode: "resize",
    predictiveBackGestureEnabled: true,
    blockedPermissions: ["android.permission.RECORD_AUDIO", "android.permission.WRITE_CONTACTS"],
    intentFilters: [
      {
        action: "VIEW",
        autoVerify: true,
        data: [{ scheme: "https", host: "tab-it.app", pathPrefix: "/join/" }],
        category: ["BROWSABLE", "DEFAULT"],
      },
    ],
  },
  plugins: [
    "expo-router",
    "expo-apple-authentication",
    "expo-secure-store",
    "expo-sqlite",
    "expo-localization",
    "expo-web-browser",
    "@react-native-community/datetimepicker",
    [
      "expo-splash-screen",
      {
        image: "./assets/splash-icon.png",
        imageWidth: 160,
        backgroundColor: "#FAF7F0",
      },
    ],
    [
      "expo-notifications",
      {
        color: "#4F7549",
        enableBackgroundRemoteNotifications: false,
      },
    ],
    [
      "expo-contacts",
      { contactsPermission: "tab-it uses your contacts so you can add a friend by their email address." },
    ],
    [
      "expo-image-picker",
      {
        photosPermission: "tab-it uses your photo library so you can attach a receipt to an expense.",
        cameraPermission: "tab-it uses the camera so you can photograph a receipt for an expense.",
        microphonePermission: false,
      },
    ],
  ],
  experiments: {
    typedRoutes: true,
  },
};

export default config;
