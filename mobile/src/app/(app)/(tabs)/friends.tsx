import { router } from "expo-router";
import { useMemo, useState } from "react";
import { RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { allTripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { formatMoney, friendsList } from "@/domain";
import { SyncBanner } from "@/features/sync/sync-banner";
import { Avatar } from "@/ui/avatar";
import { Button, Card, Divider, EmptyState, Fab, Icon, LargeTitle, SectionHeader, useTabBarClearance } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";
import { Pressable } from "react-native";

type FriendRow = ReturnType<typeof friendsList>["active"][number];

export default function Friends() {
  const ctx = useSignedIn();
  const state = useAppState();
  const [refreshing, setRefreshing] = useState(false);
  const clearance = useTabBarClearance();
  const list = useMemo(() => friendsList(allTripRows(state), ctx.user.id), [state, ctx.user.id]);

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
        <LargeTitle title="Friends" />
        <SyncBanner />
        {list.isEmpty ? (
          <EmptyState
            icon="people-outline"
            title="No friends yet"
            message="Add an expense or start a trip to see who owes who."
            action={<Button title="Add an expense" icon="add" onPress={() => router.push("/new-expense")} />}
          />
        ) : (
          <>
            {list.overall.length > 0 && (
              <Card style={{ padding: 16, gap: 6 }}>
                <Text style={styles.eyebrow}>OVERALL</Text>
                {list.overall.map((o) => (
                  <Text key={o.id} style={styles.overall}>
                    {o.youOwe > 0n && (
                      <>
                        You owe <Text style={{ color: colors.owe, fontWeight: "600" }}>{formatMoney(o.youOwe, o.currency)}</Text>
                      </>
                    )}
                    {o.youOwe > 0n && o.youAreOwed > 0n && <Text style={{ color: colors.textTertiary }}>{"  ·  "}</Text>}
                    {o.youAreOwed > 0n && (
                      <>
                        {o.youOwe > 0n ? "you're owed " : "You're owed "}
                        <Text style={{ color: colors.owed, fontWeight: "600" }}>{formatMoney(o.youAreOwed, o.currency)}</Text>
                      </>
                    )}
                  </Text>
                ))}
              </Card>
            )}
            {list.active.length > 0 && (
              <>
                <SectionHeader title="People" />
                <Card>
                  {list.active.map((f, i) => (
                    <FriendItem key={f.id} friend={f} first={i === 0} />
                  ))}
                </Card>
              </>
            )}
            {list.settled.length > 0 && (
              <>
                <SectionHeader title="Settled up" />
                <Card>
                  {list.settled.map((f, i) => (
                    <FriendItem key={f.id} friend={f} first={i === 0} />
                  ))}
                </Card>
              </>
            )}
          </>
        )}
      </ScrollView>
      <Fab label="Add expense" bottom={clearance + 12} onPress={() => router.push("/new-expense")} />
    </SafeAreaView>
  );
}

function FriendItem({ friend, first }: { friend: FriendRow; first: boolean }) {
  const avatar =
    friend.friend.type === "user"
      ? { id: friend.friend.id, name: friend.displayName }
      : { id: friend.friend.email, name: friend.displayName, email: friend.friend.email, pending: true };
  return (
    <View>
      {!first && <Divider inset={68} />}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${friend.displayName}. ${friend.lines.map((l) => `${l.label} ${l.amount}`).join(", ") || "all settled"}`}
        onPress={() => router.push({ pathname: "/friend/[key]", params: { key: friend.id } })}
        style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surface2 }]}
      >
        <Avatar person={avatar} size={42} ring={0} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={styles.name} numberOfLines={1}>
            {friend.displayName}
          </Text>
          <Text style={styles.sub} numberOfLines={1}>
            {friend.isPending ? "Invite pending" : friend.isSettled ? "all settled" : friend.subtitle}
          </Text>
        </View>
        <View style={{ alignItems: "flex-end", gap: 2 }}>
          {friend.lines.map((l) => (
            <View key={l.id} style={{ alignItems: "flex-end" }}>
              <Text style={styles.lineLabel}>{l.label.toUpperCase()}</Text>
              <Text style={[styles.lineAmount, { color: l.isPositive ? colors.owed : colors.owe }]}>{l.amount}</Text>
            </View>
          ))}
        </View>
        <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  eyebrow: { fontSize: 11, fontWeight: "600", letterSpacing: 1.3, color: colors.textSecondary },
  overall: { fontSize: 15, color: colors.textSecondary, fontVariant: ["tabular-nums"] },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 14, paddingVertical: 12 },
  name: { fontSize: 16, fontWeight: "500", color: colors.text },
  sub: { fontSize: 13, color: colors.textSecondary, marginTop: 2 },
  lineLabel: { fontSize: 9.5, fontWeight: "600", letterSpacing: 0.8, color: colors.textSecondary },
  lineAmount: { fontSize: 16, fontWeight: "700", fontVariant: ["tabular-nums"] },
});
