import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, RefreshControl, ScrollView, Share, StyleSheet, Text, View } from "react-native";

import { setTripMuted } from "@/data/actions";
import { isDirty } from "@/data/schema";
import { onlineMessage, revokeTripInvite, tripInviteUrl } from "@/data/online";
import { useTripRealtime } from "@/data/realtime";
import { mutedTripIds, tripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { balanceSummaries, overview as buildOverview, simplifiedGroups, sortedPeople, timelineDays } from "@/domain";
import { BalanceCard, DebtGroups, SettledCard, Timeline } from "@/features/ledger/components";
import { OverviewSection } from "@/features/ledger/overview";
import { shareTripExport } from "@/features/trip/export";
import { SyncBanner } from "@/features/sync/sync-banner";
import { AvatarGroup } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { MoreMenu } from "@/ui/menu";
import { Button, EmptyState, Fab, Segmented } from "@/ui/primitives";
import { colors, PAGE, type } from "@/ui/theme";

type Segment = "expenses" | "balances" | "overview";

export default function TripScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const [segment, setSegment] = useState<Segment>("expenses");
  const [refreshing, setRefreshing] = useState(false);
  useTripRealtime(id);

  const trip = state.tables.trips.get(id);
  const rows = useMemo(() => tripRows(state, id), [state, id]);
  const me = rows?.people.find((p) => p.user_id === ctx.user.id);
  const isNonGroup = trip?.kind === "non_group";

  const derived = useMemo(() => {
    if (!rows || !me) return null;
    const people = rows.people;
    const categories = rows.categories ?? [];
    const names = (pid: string) => (pid === me.id ? "You" : (people.find((p) => p.id === pid)?.display_name ?? "Member"));
    const youPeople = people.map((p) => (p.id === me.id ? { ...p, display_name: "You" } : p));
    return {
      summaries: balanceSummaries(rows, youPeople, me.id),
      groups: simplifiedGroups(rows, youPeople, me.id),
      days: timelineDays(rows, youPeople, categories, me.id),
      overview: buildOverview(rows, me.id, names, (cid) => categories.find((c) => c.id === cid)?.name ?? "Other"),
      categoryIcon: (cid: string | null) => categories.find((c) => c.id === cid)?.icon ?? null,
      pending: new Set(rows.expenses.filter((e) => isDirty(e as never)).map((e) => e.id)),
      members: sortedPeople(people.filter((p) => !p.removed_at), me.id).map((p) => ({
        id: p.id,
        name: p.id === me.id ? ctx.user.displayName : p.display_name,
        email: p.email,
        pending: !p.user_id,
      })),
    };
  }, [rows, me, ctx.user.displayName]);

  if (!trip || trip.deleted_at || !rows || !me || !derived) {
    return (
      <>
        <Stack.Screen options={{ title: "" }} />
        <EmptyState
          icon="help-circle-outline"
          title="Trip not found"
          message="It may have been deleted, or you were removed from it."
          action={<Button title="Back" variant="secondary" onPress={() => router.back()} />}
        />
      </>
    );
  }

  const muted = mutedTripIds(state, ctx.user.id).has(id);
  const title = isNonGroup ? derived.members.filter((m) => m.id !== me.id).map((m) => m.name).join(", ") : trip.name;

  async function shareInvite() {
    try {
      const url = await tripInviteUrl(ctx, id);
      await Share.share({ message: `Join "${trip!.name}" on tab-it: ${url}`, url });
    } catch (error) {
      Alert.alert("Invite link unavailable", onlineMessage(error));
    }
  }

  function confirmRevoke() {
    Alert.alert("Turn off invite link?", "People with the old link won't be able to join. Sharing again creates a new link.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Turn off",
        style: "destructive",
        onPress: () => revokeTripInvite(ctx, id).catch((e) => Alert.alert("Couldn't turn off the link", onlineMessage(e))),
      },
    ]);
  }

  const menu = [
    ...(isNonGroup ? [] : [{ id: "edit", title: "Edit trip", symbol: "pencil", onPress: () => router.push({ pathname: "/trip-edit", params: { id } }) }]),
    { id: "people", title: "People", symbol: "person.2", onPress: () => router.push({ pathname: "/trip-people", params: { id } }) },
    { id: "settle", title: "Record a payment", symbol: "arrow.left.arrow.right", onPress: () => router.push({ pathname: "/settle-up", params: { tripId: id } }) },
    {
      id: "mute",
      title: muted ? "Unmute notifications" : "Mute notifications",
      symbol: muted ? "bell" : "bell.slash",
      onPress: () => {
        haptics.light();
        void setTripMuted(ctx, id, !muted);
      },
    },
    ...(isNonGroup
      ? []
      : [
          { id: "invite", title: "Share invite link", symbol: "person.badge.plus", onPress: () => void shareInvite() },
          { id: "revoke", title: "Turn off invite link", symbol: "link.badge.minus", destructive: true, onPress: confirmRevoke },
        ]),
    {
      id: "export",
      title: "Export spreadsheet",
      symbol: "square.and.arrow.up",
      onPress: () => shareTripExport(rows, trip.name).catch((e: Error) => Alert.alert("Couldn't export", e.message)),
    },
  ];

  return (
    <View style={styles.fill}>
      <Stack.Screen
        options={{
          title: "",
          headerTitle: () => (
            <AvatarGroup people={derived.members} size={30} max={4} onAdd={isNonGroup ? undefined : () => router.push({ pathname: "/trip-people", params: { id } })} />
          ),
          headerRight: () => <MoreMenu items={menu} label="Trip actions" />,
        }}
      />
      <ScrollView
        contentContainerStyle={styles.content}
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
        <Text style={[type.largeTitle, styles.title]} numberOfLines={2}>
          {title}
        </Text>
        <SyncBanner />
        {derived.summaries.length > 0 ? (
          derived.summaries.map((s) => <BalanceCard key={s.label + s.amount} summary={s} />)
        ) : (
          <SettledCard
            title={rows.expenses.some((e) => !e.deleted_at) ? "All settled" : "No expenses yet"}
            message={rows.expenses.some((e) => !e.deleted_at) ? "Nobody owes anything right now." : "Add the first expense to start tracking."}
          />
        )}
        <Segmented
          style={{ marginTop: 2, marginBottom: 6 }}
          value={segment}
          onChange={setSegment}
          options={[
            { value: "expenses", label: "Expenses" },
            { value: "balances", label: "Balances" },
            { value: "overview", label: "Overview" },
          ]}
        />
        {segment === "expenses" &&
          (derived.days.length > 0 ? (
            <Timeline
              days={derived.days}
              pendingIds={derived.pending}
              onOpenExpense={(eid) => router.push({ pathname: "/expense/[id]", params: { id: eid } })}
              onOpenSettlement={(sid) => router.push({ pathname: "/settlement/[id]", params: { id: sid } })}
            />
          ) : (
            <EmptyState icon="receipt-outline" title="No expenses yet" message="Tap Add expense to log the first one." />
          ))}
        {segment === "balances" &&
          (derived.groups.length > 0 ? (
            <View style={{ paddingTop: 10 }}>
              <DebtGroups
                groups={derived.groups}
                onSettle={(debt) =>
                  router.push({
                    pathname: "/settle-up",
                    params: {
                      tripId: id,
                      from: debt.suggestion.fromPersonID,
                      to: debt.suggestion.toPersonID,
                      currency: debt.suggestion.currency,
                      amount: debt.suggestion.amount.toString(),
                    },
                  })
                }
              />
              <Text style={styles.hint}>Tap a balance to record a payment. Balances are simplified so the group needs as few payments as possible.</Text>
            </View>
          ) : (
            <EmptyState icon="checkmark-circle-outline" title="Everyone's settled" message="Balances appear here once there are expenses." />
          ))}
        {segment === "overview" && (
          <View style={{ paddingTop: 10 }}>
            <OverviewSection overview={derived.overview} categoryIcon={derived.categoryIcon} />
          </View>
        )}
      </ScrollView>
      <Fab label="Add expense" onPress={() => router.push({ pathname: "/expense-form", params: { tripId: id } })} />
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  content: { paddingBottom: 120 },
  title: { paddingHorizontal: PAGE, paddingTop: 4, paddingBottom: 14 },
  hint: { fontSize: 12, color: colors.textSecondary, paddingHorizontal: PAGE + 8, paddingTop: 2, lineHeight: 17 },
});
