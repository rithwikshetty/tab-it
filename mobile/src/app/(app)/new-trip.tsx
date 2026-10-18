import { router, Stack } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

import { addPeople, createTrip } from "@/data/actions";
import { useSignedIn } from "@/data/session";
import { PeoplePicker, type PickedPerson } from "@/features/people/people-picker";
import { haptics } from "@/ui/haptics";
import { Field, HeaderButton, Icon, SectionHeader } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

export default function NewTrip() {
  const ctx = useSignedIn();
  const [name, setName] = useState("");
  const [people, setPeople] = useState<PickedPerson[]>([]);
  const [saving, setSaving] = useState(false);
  const canCreate = name.trim().length > 0 && !saving;

  async function create() {
    if (!canCreate) return;
    setSaving(true);
    const tripId = await createTrip(ctx, name);
    if (people.length > 0) await addPeople(ctx, tripId, people);
    haptics.success();
    router.dismiss();
    router.push({ pathname: "/trip/[id]", params: { id: tripId } });
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen
        options={{
          headerLeft: () => <HeaderButton title="Cancel" onPress={() => router.back()} />,
          headerRight: () => <HeaderButton title="Create" bold disabled={!canCreate} onPress={create} />,
        }}
      />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 40 }}>
        <View style={styles.section}>
          <Field
            label="Trip name"
            value={name}
            onChangeText={setName}
            placeholder="Lisbon weekend"
            autoFocus
            autoCapitalize="words"
            returnKeyType="done"
            maxLength={100}
            onSubmitEditing={create}
          />
          <Text style={styles.hint}>Only people you add can see the trip. They'll see it when they sign in with that email.</Text>
        </View>
        <SectionHeader title="People" />
        <PeoplePicker selected={people} onChange={setPeople} />
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push("/import-splitwise")}
          style={({ pressed }) => [styles.import, pressed && { opacity: 0.7 }]}
        >
          <Icon name="download-outline" size={18} color={colors.accentStrong} />
          <Text style={styles.importText}>Import a group from Splitwise</Text>
          <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
        </Pressable>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  section: { paddingHorizontal: PAGE, paddingTop: 16, gap: 8 },
  hint: { fontSize: 13, color: colors.textSecondary, lineHeight: 18 },
  import: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    marginHorizontal: PAGE,
    marginTop: 28,
    padding: 16,
    borderRadius: radius.card,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.cardBorder,
  },
  importText: { flex: 1, fontSize: 15, fontWeight: "500", color: colors.accentStrong },
});
