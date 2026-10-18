import { router, Stack, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { Alert, ScrollView, StyleSheet, Text, View } from "react-native";

import { deleteTrip, renameTrip } from "@/data/actions";
import { useAppState, useSignedIn } from "@/data/session";
import { haptics } from "@/ui/haptics";
import { Button, Field, HeaderButton } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

export default function TripEdit() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const ctx = useSignedIn();
  const trip = useAppState().tables.trips.get(id);
  const [name, setName] = useState(trip?.name ?? "");
  const canSave = !!trip && name.trim().length > 0 && name.trim() !== trip.name;

  async function save() {
    if (!canSave) return;
    await renameTrip(ctx, id, name);
    haptics.success();
    router.back();
  }

  function confirmDelete() {
    Alert.alert("Delete trip?", `"${trip?.name}" and its expenses will be removed for everyone in it.`, [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete trip",
        style: "destructive",
        onPress: async () => {
          await deleteTrip(ctx, id);
          haptics.success();
          router.dismissAll();
        },
      },
    ]);
  }

  return (
    <ScrollView style={styles.fill} keyboardShouldPersistTaps="handled">
      <Stack.Screen
        options={{
          title: "Edit trip",
          headerLeft: () => <HeaderButton title="Cancel" onPress={() => router.back()} />,
          headerRight: () => <HeaderButton title="Save" bold disabled={!canSave} onPress={save} />,
        }}
      />
      <View style={styles.section}>
        <Field label="Trip name" value={name} onChangeText={setName} autoFocus autoCapitalize="words" maxLength={100} returnKeyType="done" onSubmitEditing={save} />
      </View>
      <View style={[styles.section, { marginTop: 40 }]}>
        <Button title="Delete trip" variant="destructive" icon="trash-outline" onPress={confirmDelete} />
        <Text style={styles.hint}>Deleting removes the trip for everyone. Balances in it stop counting towards your friends' totals.</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  section: { paddingHorizontal: PAGE, paddingTop: 16, gap: 8 },
  hint: { fontSize: 13, color: colors.textSecondary, textAlign: "center", lineHeight: 18 },
});
