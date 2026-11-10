import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { StyleSheet, Text, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { signOutWithoutStore } from "@/data/auth";
import { SessionProvider, useSession } from "@/data/session";
import { config } from "@/lib/config";
import { Button } from "@/ui/primitives";
import { colors, type } from "@/ui/theme";

SplashScreen.preventAutoHideAsync().catch(() => undefined);

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={styles.fill}>
      <SafeAreaProvider>
        <StatusBar style="dark" />
        {config.isConfigured ? (
          <SessionProvider>
            <RootNavigator />
          </SessionProvider>
        ) : (
          <MissingConfig />
        )}
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

function RootNavigator() {
  const { status, retry } = useSession();
  useEffect(() => {
    if (status !== "loading") SplashScreen.hideAsync().catch(() => undefined);
  }, [status]);
  if (status === "loading") return null;
  if (status === "failed") return <StoreFailed onRetry={retry} />;
  return (
    <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.bg } }}>
      <Stack.Protected guard={status === "signedIn"}>
        <Stack.Screen name="(app)" />
      </Stack.Protected>
      <Stack.Protected guard={status === "signedOut"}>
        <Stack.Screen name="sign-in" />
      </Stack.Protected>
      <Stack.Screen name="join/[token]" />
      <Stack.Screen name="auth-callback" />
    </Stack>
  );
}

/** Signed in, but the local store wouldn't open. */
function StoreFailed({ onRetry }: { onRetry: () => void }) {
  return (
    <View style={styles.missing}>
      <Text style={type.title}>Couldn't open your trips</Text>
      <Text style={[type.small, { textAlign: "center", marginTop: 8, marginBottom: 20 }]}>
        tab-it couldn't read what's saved on this phone. Everything that has synced is safe on the server.
      </Text>
      <View style={{ alignSelf: "stretch", gap: 10 }}>
        <Button title="Try again" onPress={onRetry} />
        <Button title="Sign out" variant="secondary" onPress={() => void signOutWithoutStore()} />
      </View>
    </View>
  );
}

function MissingConfig() {
  useEffect(() => {
    SplashScreen.hideAsync().catch(() => undefined);
  }, []);
  return (
    <View style={styles.missing}>
      <Text style={type.title}>No backend configured</Text>
      <Text style={[type.small, { textAlign: "center", marginTop: 8 }]}>
        Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY for this build. See mobile/README.md.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  missing: { flex: 1, alignItems: "center", justifyContent: "center", padding: 32, backgroundColor: colors.bg },
});
