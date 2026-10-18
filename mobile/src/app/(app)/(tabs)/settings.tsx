import * as Application from "expo-application";
import { router, useFocusEffect } from "expo-router";
import * as WebBrowser from "expo-web-browser";
import { useCallback, useState } from "react";
import { Alert, Linking, Platform, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { updateDisplayName } from "@/data/actions";
import { deleteAccount, signOut } from "@/data/auth";
import { pushPermission, registerForPush, type PushPermission } from "@/data/push";
import { unsyncedChanges } from "@/data/selectors";
import { useAppState, useSignedIn, useSyncStatus } from "@/data/session";
import { CurrencyPicker } from "@/features/currency/currency-picker";
import { rememberCurrency, savedCurrency } from "@/features/currency/defaults";
import { JoinByLink } from "@/features/settings/join-by-link";
import { PRIVACY_URL } from "@/lib/config";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, Icon, LargeTitle, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

const SUPPORT_EMAIL = "support@tab-it.app";

function presentableEmail(email: string | null): string | null {
  if (!email) return null;
  return email.endsWith("@privaterelay.appleid.com") ? "Email hidden by Apple" : email;
}

function ago(date: Date | null): string {
  if (!date) return "Not yet";
  const s = Math.round((Date.now() - date.getTime()) / 1000);
  if (s < 45) return "Just now";
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  return h < 24 ? `${h} h ago` : date.toLocaleDateString();
}

export default function Settings() {
  const ctx = useSignedIn();
  const state = useAppState();
  const status = useSyncStatus();
  const [editingName, setEditingName] = useState(false);
  const profileName = state.tables.profiles.get(ctx.user.id)?.display_name ?? ctx.user.displayName;
  const [name, setName] = useState(profileName);
  const [push, setPush] = useState<PushPermission>("undetermined");
  const [pickingCurrency, setPickingCurrency] = useState(false);
  const [joining, setJoining] = useState(false);
  const [busy, setBusy] = useState<"signout" | "delete" | null>(null);
  const [syncing, setSyncing] = useState(false);
  const currency = savedCurrency(state);

  useFocusEffect(
    useCallback(() => {
      void pushPermission().then(setPush);
    }, []),
  );

  async function saveName() {
    try {
      await updateDisplayName(ctx, name);
      haptics.success();
      setEditingName(false);
    } catch (e) {
      Alert.alert("Couldn't save", (e as Error).message);
    }
  }

  async function doSignOut() {
    setBusy("signout");
    try {
      await signOut({ userId: ctx.user.id, store: ctx.store, sync: ctx.sync });
    } finally {
      setBusy(null);
    }
  }

  function confirmSignOut() {
    const unsent = unsyncedChanges(state).length;
    if (unsent === 0) {
      Alert.alert("Sign out?", "Your trips stay on the server. Sign back in any time to see them.", [
        { text: "Cancel", style: "cancel" },
        { text: "Sign out", style: "destructive", onPress: doSignOut },
      ]);
      return;
    }
    Alert.alert(
      "You have unsynced changes",
      `${unsent === 1 ? "1 change hasn't" : `${unsent} changes haven't`} reached the server yet. Signing out now deletes ${unsent === 1 ? "it" : "them"} from this phone.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Sync first",
          onPress: async () => {
            await ctx.sync.refresh();
            const left = unsyncedChanges(ctx.store.getState()).length;
            if (left === 0) void doSignOut();
            else Alert.alert("Still not synced", "Connect to the internet, then try again. Nothing was signed out.");
          },
        },
        { text: "Sign out anyway", style: "destructive", onPress: doSignOut },
      ],
    );
  }

  function confirmDelete() {
    Alert.alert(
      "Delete your account?",
      "This permanently deletes your account. Trips only you joined are erased, including their expenses. In shared trips, expenses stay visible to other members, but your email and profile are removed. This cannot be undone.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Delete account",
          style: "destructive",
          onPress: async () => {
            setBusy("delete");
            try {
              await deleteAccount({ userId: ctx.user.id, store: ctx.store, sync: ctx.sync });
            } catch (e) {
              Alert.alert("Couldn't delete account", (e as Error).message);
            } finally {
              setBusy(null);
            }
          },
        },
      ],
    );
  }

  const syncLabel =
    status.phase === "syncing"
      ? "Syncing…"
      : status.phase === "offline"
        ? status.pending > 0
          ? `Offline · ${status.pending} waiting`
          : "Offline"
        : status.failed > 0
          ? `${status.failed} couldn't be saved`
          : status.pending > 0
            ? `${status.pending} waiting`
            : `Up to date · ${ago(status.lastSyncedAt)}`;

  const pushLabel = {
    granted: "On",
    denied: "Off. Turn them on in Settings.",
    undetermined: "Not set up yet",
    unsupported:
      Platform.OS === "android" ? "Coming to Android later. Activity shows every update meanwhile." : "Not available on this device",
  }[push];

  return (
    <SafeAreaView style={styles.fill} edges={["top"]}>
      <ScrollView contentContainerStyle={{ paddingBottom: 60 }} keyboardShouldPersistTaps="handled">
        <LargeTitle title="Settings" />

        <Card>
          {editingName ? (
            <View style={styles.nameEdit}>
              <TextInput
                value={name}
                onChangeText={setName}
                autoFocus
                maxLength={60}
                style={styles.nameInput}
                returnKeyType="done"
                onSubmitEditing={saveName}
                accessibilityLabel="Your name"
              />
              <Button title="Save" onPress={saveName} disabled={!name.trim()} style={{ minHeight: 40 }} />
            </View>
          ) : (
            <Row
              title={profileName}
              subtitle={presentableEmail(ctx.user.email) ?? undefined}
              right={<Text style={styles.link}>Edit</Text>}
              onPress={() => {
                setName(profileName);
                setEditingName(true);
              }}
              accessibilityLabel={`Your name, ${profileName}. Edit`}
            />
          )}
        </Card>
        <Text style={styles.footnote}>Friends see this name on trips you share.</Text>

        <SectionHeader title="Sync" />
        <Card>
          <Row
            left={
              <Icon
                name={status.phase === "offline" ? "cloud-offline-outline" : status.failed ? "alert-circle-outline" : "cloud-done-outline"}
                color={status.failed ? colors.warning : colors.accentStrong}
              />
            }
            title="Status"
            value={syncLabel}
          />
          <Divider inset={48} />
          <Row
            left={<Icon name="refresh" color={colors.accentStrong} />}
            title={syncing ? "Syncing…" : "Sync now"}
            disabled={syncing}
            onPress={async () => {
              setSyncing(true);
              await ctx.sync.refresh();
              setSyncing(false);
            }}
          />
          {(status.pending > 0 || status.failed > 0) && (
            <>
              <Divider inset={48} />
              <Row
                left={<Icon name="list-outline" color={colors.accentStrong} />}
                title="Review unsynced changes"
                chevron
                onPress={() => router.push("/sync-issues")}
              />
            </>
          )}
        </Card>

        <SectionHeader title="Notifications" />
        <Card>
          <Row
            left={
              <Icon
                name={push === "granted" ? "notifications" : "notifications-off-outline"}
                color={push === "granted" ? colors.accentStrong : colors.textSecondary}
              />
            }
            title="Push notifications"
            subtitle={pushLabel}
            right={
              push === "denied" ? (
                <Text style={styles.link} onPress={() => Linking.openSettings()}>
                  Open Settings
                </Text>
              ) : push === "undetermined" ? (
                <Text style={styles.link} onPress={() => registerForPush(true).then(setPush)}>
                  Turn on
                </Text>
              ) : undefined
            }
          />
        </Card>

        <SectionHeader title="Preferences" />
        <Card>
          <Row
            left={<Icon name="cash-outline" color={colors.accentStrong} />}
            title="Default currency"
            value={currency ?? "Automatic"}
            chevron
            onPress={() => setPickingCurrency(true)}
          />
        </Card>
        <Text style={styles.footnote}>New expenses use the trip's latest currency. This is the fallback for new trips.</Text>

        <SectionHeader title="Trips" />
        <Card>
          <Row
            left={<Icon name="link-outline" color={colors.accentStrong} />}
            title="Join a trip with an invite link"
            chevron
            onPress={() => setJoining(true)}
          />
          <Divider inset={48} />
          <Row
            left={<Icon name="download-outline" color={colors.accentStrong} />}
            title="Import from Splitwise"
            chevron
            onPress={() => router.push("/import-splitwise")}
          />
        </Card>

        <SectionHeader title="About" />
        <Card>
          <Row
            left={<Icon name="shield-checkmark-outline" color={colors.accentStrong} />}
            title="Privacy policy"
            chevron
            onPress={() => WebBrowser.openBrowserAsync(PRIVACY_URL)}
          />
          <Divider inset={48} />
          <Row
            left={<Icon name="mail-outline" color={colors.accentStrong} />}
            title="Contact support"
            value={SUPPORT_EMAIL}
            onPress={() => Linking.openURL(`mailto:${SUPPORT_EMAIL}`)}
          />
          <Divider inset={48} />
          <Row
            left={<Icon name="information-circle-outline" color={colors.accentStrong} />}
            title="Version"
            value={`${Application.nativeApplicationVersion ?? "?"} (${Application.nativeBuildVersion ?? "?"})`}
          />
        </Card>

        <View style={{ paddingHorizontal: PAGE, gap: 4, marginTop: 18 }}>
          <Button title="Sign out" variant="destructive" loading={busy === "signout"} disabled={busy !== null} onPress={confirmSignOut} />
          <Button
            title="Delete account"
            variant="destructive"
            loading={busy === "delete"}
            disabled={busy !== null}
            onPress={confirmDelete}
          />
        </View>
      </ScrollView>
      <CurrencyPicker
        visible={pickingCurrency}
        value={currency ?? ""}
        onPick={(code) => rememberCurrency(ctx, code)}
        onClose={() => setPickingCurrency(false)}
      />
      <JoinByLink visible={joining} onClose={() => setJoining(false)} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  link: { fontSize: 14, fontWeight: "600", color: colors.accentStrong },
  footnote: { fontSize: 12.5, color: colors.textSecondary, paddingHorizontal: PAGE + 8, marginTop: -6, lineHeight: 17 },
  nameEdit: { flexDirection: "row", alignItems: "center", gap: 10, padding: 10, paddingLeft: 16 },
  nameInput: { flex: 1, fontSize: 16, color: colors.text, paddingVertical: 8 },
});
