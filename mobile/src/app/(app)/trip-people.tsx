import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, Share, StyleSheet, Text, View } from "react-native";

import { addPeople } from "@/data/actions";
import { onlineMessage, removeTripPerson, tripInviteUrl, updateTripPersonEmail } from "@/data/online";
import { peopleInTrip } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { hasPlaceholderEmail, sortedPeople } from "@/domain";
import type { LocalPerson } from "@/data/schema";
import { PersonEmailSheet } from "@/features/people/email-sheet";
import { PeoplePicker, type PickedPerson } from "@/features/people/people-picker";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, HeaderButton, SectionHeader } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

export default function TripPeople() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const [adding, setAdding] = useState<PickedPerson[]>([]);
  const [editing, setEditing] = useState<LocalPerson | null>(null);

  const trip = state.tables.trips.get(id);
  const people = useMemo(() => {
    const list = peopleInTrip(state, id);
    const me = list.find((p) => p.user_id === ctx.user.id);
    return sortedPeople(list, me?.id ?? null) as LocalPerson[];
  }, [state, id, ctx.user.id]);

  async function addSelected() {
    await addPeople(ctx, id, adding);
    haptics.success();
    setAdding([]);
  }

  function personActions(person: LocalPerson) {
    if (person.user_id === ctx.user.id) return;
    const buttons: { text: string; style?: "destructive" | "cancel"; onPress?: () => void }[] = [];
    if (!person.user_id)
      buttons.push({ text: hasPlaceholderEmail(person) ? "Add their email" : "Change email", onPress: () => setEditing(person) });
    buttons.push({
      text: "Remove from trip",
      style: "destructive",
      onPress: () =>
        Alert.alert(
          `Remove ${person.display_name}?`,
          "Their expenses and balances stay in the trip. You can add them back later with the same email.",
          [
            { text: "Cancel", style: "cancel" },
            {
              text: "Remove",
              style: "destructive",
              onPress: () => removeTripPerson(ctx, person.id).catch((e) => Alert.alert("Couldn't remove", onlineMessage(e))),
            },
          ],
        ),
    });
    buttons.push({ text: "Cancel", style: "cancel" });
    Alert.alert(person.display_name, hasPlaceholderEmail(person) ? "No email yet" : person.email, buttons);
  }

  async function shareInvite() {
    try {
      const url = await tripInviteUrl(ctx, id);
      await Share.share({ message: `Join "${trip?.name}" on tab-it: ${url}`, url });
    } catch (error) {
      Alert.alert("Invite link unavailable", onlineMessage(error));
    }
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen
        options={{
          title: trip?.name ? `People in ${trip.name}` : "People",
          headerRight: () => <HeaderButton title="Done" bold onPress={() => router.back()} />,
        }}
      />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 40 }}>
        <SectionHeader title={`${people.length} ${people.length === 1 ? "person" : "people"}`} first />
        <Card>
          {people.map((p, i) => {
            const isMe = p.user_id === ctx.user.id;
            const status = p.joined_at ? null : p._pushed === null ? "Not synced yet" : hasPlaceholderEmail(p) ? "No email" : "Pending";
            return (
              <View key={p.id}>
                {i > 0 && <Divider inset={62} />}
                <Pressable
                  disabled={isMe}
                  accessibilityRole="button"
                  accessibilityLabel={`${isMe ? "You" : p.display_name}${status ? `, ${status}` : ""}`}
                  onPress={() => personActions(p)}
                  style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surface2 }]}
                >
                  <Avatar
                    person={{ id: p.id, name: isMe ? ctx.user.displayName : p.display_name, userId: p.user_id, email: p.email }}
                    size={36}
                    ring={0}
                  />
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.name} numberOfLines={1}>
                      {isMe ? `${p.display_name} (you)` : p.display_name}
                    </Text>
                    <Text style={styles.email} numberOfLines={1} ellipsizeMode="middle">
                      {hasPlaceholderEmail(p) ? "No email yet" : p.email}
                    </Text>
                  </View>
                  {status && (
                    <View style={styles.badge}>
                      <Text style={styles.badgeText}>{status}</Text>
                    </View>
                  )}
                </Pressable>
              </View>
            );
          })}
        </Card>
        <Text style={styles.hint}>
          Pending people join when they open tab-it signed in with that email. Tap someone to add or change their email, or to remove them.
        </Text>

        {trip?.kind === "trip" && (
          <View style={{ paddingHorizontal: PAGE, paddingTop: 16 }}>
            <Button title="Share invite link" icon="link-outline" variant="secondary" onPress={shareInvite} />
          </View>
        )}

        <SectionHeader title="Add people" />
        <PeoplePicker selected={adding} onChange={setAdding} exclude={people.map((p) => p.email)} />
        {adding.length > 0 && (
          <View style={{ paddingHorizontal: PAGE, paddingTop: 14 }}>
            <Button
              title={adding.length === 1 ? `Add ${adding[0]!.displayName}` : `Add ${adding.length} people`}
              icon="person-add-outline"
              onPress={addSelected}
            />
          </View>
        )}
      </ScrollView>
      {editing && (
        <PersonEmailSheet
          name={editing.display_name}
          initialEmail={hasPlaceholderEmail(editing) ? "" : editing.email}
          exclude={people.filter((p) => p.id !== editing.id).map((p) => p.email)}
          onSave={(email) => updateTripPersonEmail(ctx, editing.id, email)}
          onClose={() => setEditing(null)}
        />
      )}
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 15, paddingVertical: 11 },
  name: { fontSize: 15, fontWeight: "500", color: colors.text },
  email: { fontSize: 12.5, color: colors.textSecondary, marginTop: 1 },
  badge: { paddingHorizontal: 8, paddingVertical: 3, borderRadius: radius.pill, backgroundColor: colors.surface2 },
  badgeText: { fontSize: 11, fontWeight: "600", color: colors.warning },
  hint: { fontSize: 12.5, color: colors.textSecondary, paddingHorizontal: PAGE + 8, lineHeight: 17 },
});
