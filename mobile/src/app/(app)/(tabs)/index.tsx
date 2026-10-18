import { router } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { deleteTrip } from "@/data/actions";
import { liveTrips, myPeopleByTrip, tripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { compareTimestamps } from "@/data/timestamps";
import { tripCard, type TripCardStatus } from "@/domain";
import { SyncBanner } from "@/features/sync/sync-banner";
import { AvatarGroup } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, EmptyState, Fab, IconButton, LargeTitle, Row, SectionHeader, useTabBarClearance } from "@/ui/primitives";
import { SwipeToDelete } from "@/ui/swipe-row";
import { colors } from "@/ui/theme";

export default function TripsScreen() {
  const ctx = useSignedIn();
  const state = useAppState();
  const [refreshing, setRefreshing] = useState(false);
  const clearance = useTabBarClearance();

  const cards = useMemo(() => {
    const mine = myPeopleByTrip(state, ctx.user.id);
    const now = new Date().toISOString();
    return liveTrips(state)
      .sort((a, b) => compareTimestamps(b.last_activity_at, a.last_activity_at))
      .flatMap((trip) => {
        const me = mine.get(trip.id);
        const rows = tripRows(state, trip.id);
        if (!me || !rows) return [];
        return [tripCard(rows, me.id, now, ctx.user.displayName)];
      });
  }, [state, ctx.user]);

  const active = cards.filter((c) => !c.isCompleted);
  const completed = cards.filter((c) => c.isCompleted);

  function confirmDelete(id: string, name: string) {
    Alert.alert("Delete trip?", `"${name}" will be removed for everyone.`, [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: () => {
          haptics.success();
          void deleteTrip(ctx, id);
        },
      },
    ]);
  }

  const section = (title: string, list: typeof cards) =>
    list.length > 0 && (
      <View key={title}>
        <SectionHeader title={title} />
        <Card>
          {list.map((card, i) => (
            <View key={card.id}>
              {i > 0 && <Divider />}
              <SwipeToDelete onDelete={() => confirmDelete(card.id, card.name)}>
                <View style={{ backgroundColor: colors.surface }}>
                  <Row
                    onPress={() => router.push({ pathname: "/trip/[id]", params: { id: card.id } })}
                    accessibilityLabel={`${card.name}, ${card.status.text}`}
                    title={card.name}
                    subtitle={<StatusText status={card.status} />}
                    right={
                      <AvatarGroup
                        people={card.members.map((m) => ({
                          id: m.id,
                          name: m.displayName === "You" ? ctx.user.displayName : m.displayName,
                        }))}
                        size={30}
                        max={4}
                      />
                    }
                  />
                </View>
              </SwipeToDelete>
            </View>
          ))}
        </Card>
      </View>
    );

  return (
    <SafeAreaView style={styles.fill} edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: clearance + 90 }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            tintColor={colors.accent}
            colors={[colors.accent]}
            onRefresh={async () => {
              setRefreshing(true);
              await ctx.sync.refresh();
              setRefreshing(false);
            }}
          />
        }
      >
        <LargeTitle title="Trips" right={<IconButton icon="add" size={28} label="New trip" onPress={() => router.push("/new-trip")} />} />
        <SyncBanner />
        {cards.length === 0 ? (
          <EmptyState
            icon="airplane-outline"
            title="No trips yet"
            message="Start a trip for a holiday, a flat, or anything you split costs on. Everyone you add sees the same balances."
            action={<Button title="Start a trip" icon="add" onPress={() => router.push("/new-trip")} />}
          />
        ) : (
          <>
            {section("Active", active)}
            {section("Completed", completed)}
          </>
        )}
      </ScrollView>
      <Fab label="Add expense" bottom={clearance + 12} onPress={() => router.push("/new-expense")} />
    </SafeAreaView>
  );
}

function StatusText({ status }: { status: TripCardStatus }) {
  const color = status.type === "owed" ? colors.owed : status.type === "owe" ? colors.owe : colors.textSecondary;
  return (
    <Text style={[styles.status, { color }]} numberOfLines={1}>
      {status.text || "no expenses yet"}
    </Text>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  content: { paddingBottom: 120 },
  status: { fontSize: 13, fontWeight: "500", marginTop: 2 },
});
