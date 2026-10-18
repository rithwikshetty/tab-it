import { router, Stack } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, ScrollView, StyleSheet, Text, View } from "react-native";

import { discardLocalChange } from "@/data/actions";
import { unsyncedChanges, type UnsyncedChange } from "@/data/selectors";
import { useAppState, useSignedIn, useSyncStatus } from "@/data/session";
import { Button, Card, Divider, EmptyState, HeaderButton, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

export default function SyncIssues() {
  const ctx = useSignedIn();
  const state = useAppState();
  const status = useSyncStatus();
  const [syncing, setSyncing] = useState(false);
  const changes = useMemo(() => unsyncedChanges(state), [state]);
  const failed = changes.filter((c) => c.error);
  const waiting = changes.filter((c) => !c.error);

  function confirmDiscard(change: UnsyncedChange) {
    Alert.alert("Discard this change?", "It will be removed from this phone. The server's version stays as it is.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Discard",
        style: "destructive",
        onPress: () => discardLocalChange(ctx, change.table, change.key).then(() => ctx.sync.refresh()),
      },
    ]);
  }

  const list = (items: UnsyncedChange[]) => (
    <Card>
      {items.map((c, i) => (
        <View key={`${c.table}:${c.key}`}>
          {i > 0 && <Divider inset={16} />}
          <Row
            title={c.label}
            subtitle={c.error ?? c.detail}
            titleLines={1}
            right={
              c.error ? (
                <Text style={styles.discard} onPress={() => confirmDiscard(c)}>
                  Discard
                </Text>
              ) : undefined
            }
            onPress={
              c.table === "expenses" || c.table === "receipts"
                ? () => router.push({ pathname: "/expense/[id]", params: { id: c.key } })
                : c.tripId
                  ? () => router.push({ pathname: "/trip/[id]", params: { id: c.tripId } })
                  : undefined
            }
          />
        </View>
      ))}
    </Card>
  );

  return (
    <ScrollView style={styles.fill} contentContainerStyle={{ paddingBottom: 40 }}>
      <Stack.Screen
        options={{ title: "Unsynced changes", headerRight: () => <HeaderButton title="Done" bold onPress={() => router.back()} /> }}
      />
      {changes.length === 0 ? (
        <EmptyState icon="cloud-done-outline" title="Everything is synced" message="All your changes are saved on the server." />
      ) : (
        <>
          {failed.length > 0 && (
            <>
              <SectionHeader title="Couldn't be saved" first />
              {list(failed)}
              <Text style={styles.hint}>
                The server refused these. Usually the trip was deleted or you were removed from it. Discard them, or fix and save again.
              </Text>
            </>
          )}
          {waiting.length > 0 && (
            <>
              <SectionHeader title="Waiting to sync" first={failed.length === 0} />
              {list(waiting)}
              <Text style={styles.hint}>
                {status.phase === "offline" ? "These will sync when you're back online." : "These are on their way."}
              </Text>
            </>
          )}
          <View style={{ paddingHorizontal: PAGE, paddingTop: 16 }}>
            <Button
              title="Try again now"
              icon="refresh"
              variant="secondary"
              loading={syncing}
              onPress={async () => {
                setSyncing(true);
                await ctx.sync.refresh();
                setSyncing(false);
              }}
            />
          </View>
        </>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  discard: { fontSize: 14, fontWeight: "600", color: colors.danger, paddingLeft: 8 },
  hint: { fontSize: 12.5, color: colors.textSecondary, paddingHorizontal: PAGE + 8, marginTop: -6, lineHeight: 17 },
});
