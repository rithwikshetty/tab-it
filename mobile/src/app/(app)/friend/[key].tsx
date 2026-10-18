import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

import { allTripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { friendDetail, type FriendIdentity } from "@/domain";
import { ExpenseRow, SettlementRow } from "@/features/ledger/components";
import { localOffset } from "@/lib/dates";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, EmptyState, Icon, SectionHeader } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

function identityFromKey(key: string): FriendIdentity | null {
  if (key.startsWith("u:")) return { type: "user", id: key.slice(2) };
  if (key.startsWith("e:")) return { type: "email", email: key.slice(2) };
  return null;
}

export default function FriendDetail() {
  const { key } = useLocalSearchParams<{ key: string }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const identity = identityFromKey(key);
  const detail = useMemo(
    () => (identity ? friendDetail(allTripRows(state), ctx.user.id, identity, { utcOffsetMinutes: localOffset(new Date()) }) : null),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [state, ctx.user.id, key],
  );

  if (!detail || !identity) {
    return (
      <>
        <Stack.Screen options={{ title: "" }} />
        <EmptyState
          icon="person-outline"
          title="Nothing shared yet"
          action={<Button title="Back" variant="secondary" onPress={() => router.back()} />}
        />
      </>
    );
  }

  const avatar =
    identity.type === "user"
      ? { id: identity.id, name: detail.displayName }
      : { id: identity.email, name: detail.displayName, email: identity.email, pending: true };

  return (
    <ScrollView style={styles.fill} contentContainerStyle={{ paddingBottom: 48 }}>
      <Stack.Screen options={{ title: "" }} />
      <View style={styles.hero}>
        <Avatar person={avatar} size={64} ring={0} />
        <Text style={styles.name}>{detail.displayName}</Text>
        {detail.isPending && <Text style={styles.pending}>Invite pending</Text>}
        <View style={{ marginTop: 10, gap: 4, alignItems: "center" }}>
          {detail.overall.length === 0 ? (
            <Text style={styles.settled}>All settled up</Text>
          ) : (
            detail.overall.map((l) => (
              <Text key={l.id} style={[styles.balance, { color: l.isPositive ? colors.owed : colors.owe }]}>
                {l.isPositive ? `${detail.displayName} owes you ${l.amount}` : `You owe ${detail.displayName} ${l.amount}`}
              </Text>
            ))
          )}
        </View>
      </View>

      <SectionHeader title="Balance by source" />
      {detail.sources.length === 0 ? (
        <Text style={styles.hint}>You're all settled up.</Text>
      ) : (
        <>
          <Card>
            {detail.sources.map((src, i) => (
              <View key={src.id}>
                {i > 0 && <Divider inset={16} />}
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={`${src.sourceName}: ${src.label} ${src.amount}. Record a payment`}
                  onPress={() => {
                    haptics.light();
                    router.push({
                      pathname: "/settle-up",
                      params: {
                        tripId: src.containerID,
                        from: src.suggestion.fromPersonID,
                        to: src.suggestion.toPersonID,
                        currency: src.suggestion.currency,
                        amount: src.suggestion.amount.toString(),
                      },
                    });
                  }}
                  style={({ pressed }) => [styles.source, pressed && { backgroundColor: colors.surface2 }]}
                >
                  <Icon name={src.isNonGroup ? "people-outline" : "airplane-outline"} size={18} color={colors.textSecondary} />
                  <Text style={styles.sourceName} numberOfLines={1}>
                    {src.sourceName}
                  </Text>
                  <View style={{ alignItems: "flex-end" }}>
                    <Text style={styles.sourceLabel}>{src.label.toUpperCase()}</Text>
                    <Text style={[styles.sourceAmount, { color: src.isPositive ? colors.owed : colors.owe }]}>{src.amount}</Text>
                  </View>
                  <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
                </Pressable>
              </View>
            ))}
          </Card>
          <Text style={styles.hint}>Tap a source to settle up there.</Text>
        </>
      )}

      {detail.timeline.length > 0 && <SectionHeader title="Shared history" />}
      {detail.timeline.map((day) => (
        <View key={day.id}>
          <Text style={styles.day}>{day.dateLabel.toUpperCase()}</Text>
          <Card style={{ marginBottom: 6 }}>
            {day.entries.map((entry, i) => (
              <View key={entry.id}>
                {i > 0 && <Divider inset={58} />}
                {entry.item.type === "expense" ? (
                  <ExpenseRow
                    item={entry.item.expense}
                    onPress={() => router.push({ pathname: "/expense/[id]", params: { id: entry.id } })}
                  />
                ) : (
                  <SettlementRow
                    item={entry.item.settlement}
                    onPress={() => router.push({ pathname: "/settlement/[id]", params: { id: entry.id } })}
                  />
                )}
              </View>
            ))}
          </Card>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  hero: { alignItems: "center", paddingTop: 8, paddingBottom: 12, paddingHorizontal: PAGE },
  name: { fontSize: 24, fontWeight: "700", color: colors.text, marginTop: 10 },
  pending: { fontSize: 13, color: colors.warning, marginTop: 2 },
  settled: { fontSize: 15, color: colors.textSecondary },
  balance: { fontSize: 16, fontWeight: "600", fontVariant: ["tabular-nums"] },
  source: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, paddingVertical: 12 },
  sourceName: { flex: 1, fontSize: 15, color: colors.text },
  sourceLabel: { fontSize: 9.5, fontWeight: "600", letterSpacing: 0.8, color: colors.textSecondary },
  sourceAmount: { fontSize: 15, fontWeight: "600", fontVariant: ["tabular-nums"] },
  hint: { fontSize: 12.5, color: colors.textSecondary, paddingHorizontal: PAGE + 8, marginTop: -6, lineHeight: 17 },
  day: {
    fontSize: 11,
    fontWeight: "600",
    letterSpacing: 1.3,
    color: colors.textSecondary,
    paddingHorizontal: PAGE + 8,
    paddingTop: 14,
    paddingBottom: 6,
  },
});
