import { router, Stack, useLocalSearchParams } from "expo-router";
import { Alert, ScrollView, StyleSheet, Text, View } from "react-native";

import { deleteSettlement } from "@/data/actions";
import { isDirty } from "@/data/schema";
import { useAppState, useSignedIn } from "@/data/session";
import { formatMoney } from "@/domain";
import { dateTime, dayOf, longDay } from "@/lib/dates";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { MoreMenu } from "@/ui/menu";
import { Banner, Button, Card, Divider, EmptyState, Icon, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

export default function SettlementDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const ctx = useSignedIn();
  const t = useAppState().tables;
  const s = t.settlements.get(id);

  if (!s || s.deleted_at) {
    return (
      <>
        <Stack.Screen options={{ title: "" }} />
        <EmptyState
          icon="help-circle-outline"
          title="Payment not found"
          message="It may have been deleted."
          action={<Button title="Back" variant="secondary" onPress={() => router.back()} />}
        />
      </>
    );
  }

  const people = [...t.trip_people.values()].filter((p) => p.trip_id === s.trip_id);
  const person = (pid: string) => people.find((p) => p.id === pid);
  const label = (pid: string) => (person(pid)?.user_id === ctx.user.id ? "You" : (person(pid)?.display_name ?? "Member"));
  const recordedBy = s.created_by === ctx.user.id ? "You" : (people.find((p) => p.user_id === s.created_by)?.display_name ?? "Member");

  function confirmDelete() {
    Alert.alert("Delete this payment?", "It will be removed from balances for everyone.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: async () => {
          await deleteSettlement(ctx, id);
          haptics.success();
          router.back();
        },
      },
    ]);
  }

  const party = (pid: string) => {
    const p = person(pid);
    return (
      <View style={styles.party}>
        <Avatar
          person={{
            id: pid,
            name: p?.user_id === ctx.user.id ? ctx.user.displayName : (p?.display_name ?? "?"),
            email: p?.email,
            pending: !p?.user_id,
          }}
          size={52}
          ring={0}
        />
        <Text style={styles.partyName} numberOfLines={1}>
          {label(pid)}
        </Text>
      </View>
    );
  };

  return (
    <ScrollView style={styles.fill} contentContainerStyle={{ paddingBottom: 48 }}>
      <Stack.Screen
        options={{
          title: "",
          headerRight: () => (
            <MoreMenu
              label="Payment actions"
              items={[
                {
                  id: "edit",
                  title: "Edit payment",
                  symbol: "pencil",
                  onPress: () => router.push({ pathname: "/settle-up", params: { tripId: s.trip_id, settlementId: id } }),
                },
                { id: "delete", title: "Delete payment", symbol: "trash", destructive: true, onPress: confirmDelete },
              ]}
            />
          ),
        }}
      />
      {s._error ? (
        <Banner tone="warning" text={s._error} action={{ label: "Review", onPress: () => router.push("/sync-issues") }} />
      ) : isDirty(s) ? (
        <Banner text="Saved on this phone. It will sync when you're online." />
      ) : null}
      <View style={styles.hero}>
        <Text style={styles.heroLabel}>PAYMENT</Text>
        <Text style={styles.amount} adjustsFontSizeToFit numberOfLines={1}>
          {formatMoney(s.amount, s.currency)}
        </Text>
        <View style={styles.parties}>
          {party(s.from_person_id)}
          <Icon name="arrow-forward" size={22} color={colors.settle} />
          {party(s.to_person_id)}
        </View>
      </View>
      <SectionHeader title="Details" />
      <Card>
        <Row title="Date" value={longDay(dayOf(new Date(s.settled_at)))} />
        {s.note && (
          <>
            <Divider inset={16} />
            <Row title="Note" subtitle={s.note} titleLines={1} />
          </>
        )}
        <Divider inset={16} />
        <Row title="Recorded by" value={recordedBy} />
        <Divider inset={16} />
        <Row title="Recorded at" value={dateTime(s.created_at)} />
      </Card>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  hero: {
    marginHorizontal: PAGE,
    marginTop: 6,
    padding: 20,
    borderRadius: 16,
    backgroundColor: "rgba(107,141,166,0.10)",
    borderWidth: 1,
    borderColor: "rgba(107,141,166,0.22)",
    alignItems: "center",
  },
  heroLabel: { fontSize: 11, fontWeight: "600", letterSpacing: 1.1, color: colors.settle },
  amount: { fontSize: 36, fontWeight: "700", color: colors.settle, marginTop: 4, fontVariant: ["tabular-nums"] },
  parties: { flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 18, marginTop: 18 },
  party: { alignItems: "center", gap: 6, width: 100 },
  partyName: { fontSize: 14, fontWeight: "500", color: colors.text },
});
