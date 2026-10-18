import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, Share, StyleSheet, Text, TextInput, View } from "react-native";

import { addPeople } from "@/data/actions";
import { onlineMessage, removeTripPerson, tripInviteUrl, updateTripPersonEmail } from "@/data/online";
import { peopleInTrip } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { isValidEmail, normalizedEmail, sortedPeople } from "@/domain";
import type { LocalPerson } from "@/data/schema";
import { hasPlaceholderEmail } from "@/features/people/email";
import { PeoplePicker, type PickedPerson } from "@/features/people/people-picker";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, HeaderButton, Icon, SectionHeader } from "@/ui/primitives";
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
    if (!person.user_id) buttons.push({ text: hasPlaceholderEmail(person.email) ? "Add their email" : "Change email", onPress: () => setEditing(person) });
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
    Alert.alert(person.display_name, hasPlaceholderEmail(person.email) ? "No email yet" : person.email, buttons);
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
            const status = p.joined_at ? null : p._pushed === null ? "Not synced yet" : hasPlaceholderEmail(p.email) ? "No email" : "Pending";
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
                  <Avatar person={{ id: p.id, name: isMe ? ctx.user.displayName : p.display_name, email: p.email, pending: !p.user_id }} size={36} ring={0} />
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.name} numberOfLines={1}>
                      {isMe ? `${p.display_name} (you)` : p.display_name}
                    </Text>
                    <Text style={styles.email} numberOfLines={1} ellipsizeMode="middle">
                      {hasPlaceholderEmail(p.email) ? "No email yet" : p.email}
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
        <Text style={styles.hint}>Pending people join when they sign in with that email. Tap someone to change their email or remove them.</Text>

        {trip?.kind === "trip" && (
          <View style={{ paddingHorizontal: PAGE, paddingTop: 16 }}>
            <Button title="Share invite link" icon="link-outline" variant="secondary" onPress={shareInvite} />
          </View>
        )}

        <SectionHeader title="Add people" />
        <PeoplePicker selected={adding} onChange={setAdding} exclude={people.map((p) => p.email)} />
        {adding.length > 0 && (
          <View style={{ paddingHorizontal: PAGE, paddingTop: 14 }}>
            <Button title={adding.length === 1 ? `Add ${adding[0]!.displayName}` : `Add ${adding.length} people`} icon="person-add-outline" onPress={addSelected} />
          </View>
        )}
      </ScrollView>
      {editing && <EmailEditor person={editing} onClose={() => setEditing(null)} />}
    </KeyboardAvoidingView>
  );
}

function EmailEditor({ person, onClose }: { person: LocalPerson; onClose: () => void }) {
  const ctx = useSignedIn();
  const [email, setEmail] = useState(hasPlaceholderEmail(person.email) ? "" : person.email);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const valid = isValidEmail(normalizedEmail(email)) && normalizedEmail(email) !== person.email;
  async function save() {
    setBusy(true);
    setError(null);
    try {
      await updateTripPersonEmail(ctx, person.id, email);
      haptics.success();
      onClose();
    } catch (e) {
      setError(onlineMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <View style={styles.sheet}>
      <Text style={styles.sheetTitle}>{person.display_name}'s email</Text>
      <Text style={styles.email}>They can claim this spot by signing in with this email.</Text>
      <View style={styles.inputRow}>
        <Icon name="mail-outline" size={16} color={colors.textSecondary} />
        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="name@example.com"
          placeholderTextColor={colors.textTertiary}
          autoFocus
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          style={styles.input}
          onSubmitEditing={() => valid && save()}
        />
      </View>
      {error && <Text style={[styles.email, { color: colors.danger }]}>{error}</Text>}
      <View style={{ flexDirection: "row", gap: 10 }}>
        <Button title="Cancel" variant="secondary" onPress={onClose} style={{ flex: 1 }} />
        <Button title="Save email" onPress={save} disabled={!valid} loading={busy} style={{ flex: 1 }} />
      </View>
    </View>
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
  sheet: {
    position: "absolute",
    left: 0,
    right: 0,
    bottom: 0,
    padding: 20,
    paddingBottom: 34,
    gap: 12,
    backgroundColor: colors.bg,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderTopWidth: 1,
    borderColor: colors.cardBorder,
  },
  sheetTitle: { fontSize: 17, fontWeight: "600", color: colors.text },
  inputRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 12,
    height: 48,
    borderRadius: radius.control,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.cardBorder,
  },
  input: { flex: 1, fontSize: 16, color: colors.text },
});
