import { MenuView } from "@react-native-menu/menu";
import { router, Stack } from "expo-router";
import { useMemo, useState } from "react";
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from "react-native";

import { onlineMessage, resolveNonGroupContainer } from "@/data/online";
import { liveTrips } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { compareTimestamps } from "@/data/timestamps";
import { normalizedEmail } from "@/domain";
import { PeoplePicker, type PickedPerson } from "@/features/people/people-picker";
import { Card, HeaderButton, Icon } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

/**
 * The global "Add expense": file it under a trip, or pick people for an
 * expense outside any trip. Either way it hands over to the expense form.
 */
export default function NewExpense() {
  const ctx = useSignedIn();
  const state = useAppState();
  const [tripId, setTripId] = useState<string | null>(null);
  const [people, setPeople] = useState<PickedPerson[]>([]);
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const trips = useMemo(() => liveTrips(state).sort((a, b) => compareTimestamps(b.last_activity_at, a.last_activity_at)), [state]);
  const trip = trips.find((t) => t.id === tripId);
  const canProceed = !resolving && (!!trip || people.length > 0);

  /** A non-group container already on this phone for exactly these people. */
  function localContainer(): string | null {
    const self = ctx.user.email ? normalizedEmail(ctx.user.email) : `${ctx.user.id}@users.tab`;
    const signature = [...new Set([self, ...people.map((p) => normalizedEmail(p.email))])].sort().join("|");
    for (const t of state.tables.trips.values()) {
      if (t.kind === "non_group" && !t.deleted_at && t.member_signature === signature) return t.id;
    }
    return null;
  }

  async function proceed() {
    setError(null);
    if (trip) {
      router.replace({ pathname: "/expense-form", params: { tripId: trip.id } });
      return;
    }
    const existing = localContainer();
    if (existing) {
      router.replace({ pathname: "/expense-form", params: { tripId: existing } });
      return;
    }
    setResolving(true);
    try {
      const containerId = await resolveNonGroupContainer(ctx, people);
      router.replace({ pathname: "/expense-form", params: { tripId: containerId } });
    } catch (e) {
      setError(onlineMessage(e));
      setResolving(false);
    }
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen
        options={{
          headerLeft: () => <HeaderButton title="Cancel" onPress={() => router.back()} />,
          headerRight: () => <HeaderButton title="Next" bold disabled={!canProceed} loading={resolving} onPress={proceed} />,
        }}
      />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 40 }}>
        <Card style={{ marginTop: 12 }}>
          <View style={styles.groupRow}>
            <View style={styles.groupIcon}>
              <Icon name={trip ? "airplane" : "people"} size={16} color={colors.accentStrong} />
            </View>
            <Text style={styles.groupLabel}>Group</Text>
            <MenuView
              title="File this expense under"
              actions={[
                { id: "none", title: "No group", state: tripId === null ? "on" : "off" },
                ...trips.map((t) => ({ id: t.id, title: t.name, state: (t.id === tripId ? "on" : "off") as "on" | "off" })),
              ]}
              onPressAction={({ nativeEvent }) => setTripId(nativeEvent.event === "none" ? null : nativeEvent.event)}
            >
              <View
                style={styles.dropdown}
                accessible
                accessibilityRole="button"
                accessibilityLabel={`Group: ${trip?.name ?? "No group"}. Change`}
              >
                <Text style={styles.dropdownText} numberOfLines={1}>
                  {trip?.name ?? "No group"}
                </Text>
                <Icon name="chevron-down" size={13} color={colors.accentStrong} />
              </View>
            </MenuView>
          </View>
        </Card>
        {trip ? (
          <Text style={styles.note}>Everyone in {trip.name} will be included. You can change who's in the split next.</Text>
        ) : (
          <>
            <Text style={styles.note}>Split something with friends without starting a trip. Only the people you pick will see it.</Text>
            <PeoplePicker selected={people} onChange={setPeople} />
          </>
        )}
        {error && <Text style={styles.error}>{error}</Text>}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  groupRow: { flexDirection: "row", alignItems: "center", gap: 12, padding: 14 },
  groupIcon: { width: 30, height: 30, borderRadius: 9, backgroundColor: colors.iconBg, alignItems: "center", justifyContent: "center" },
  groupLabel: { flex: 1, fontSize: 15, fontWeight: "500", color: colors.text },
  dropdown: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: radius.pill,
    backgroundColor: colors.accentTint,
    maxWidth: 190,
  },
  dropdownText: { fontSize: 14, fontWeight: "600", color: colors.accentStrong, flexShrink: 1 },
  note: { fontSize: 13, color: colors.textSecondary, paddingHorizontal: PAGE + 8, marginTop: -4, lineHeight: 18 },
  error: { fontSize: 13, color: colors.danger, paddingHorizontal: PAGE + 8, marginTop: 12 },
});
