import { useMemo, useState } from "react";
import { KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { onlineMessage } from "@/data/online";
import { knownPeople } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { isValidEmail, nameMatchScore, normalizedEmail } from "@/domain";
import { PersonRow } from "@/features/people/people-picker";
import { haptics } from "@/ui/haptics";
import { Button, Divider, Field, Icon } from "@/ui/primitives";
import { colors, radius } from "@/ui/theme";

/**
 * Links a person who hasn't joined yet to an email, so the owner of that
 * email claims their spot. People you've split with elsewhere are suggested,
 * closest name first, so an imported name can be pointed at a friend.
 */
export function PersonEmailSheet({
  name,
  initialEmail,
  exclude,
  onSave,
  onUnlink,
  onClose,
}: {
  name: string;
  /** The person's real email, or "" while they only have a placeholder. */
  initialEmail: string;
  /** Emails someone else in the trip already has. */
  exclude: readonly string[];
  /** Saves the normalised email; a thrown error is shown in the sheet. */
  onSave: (email: string) => Promise<void> | void;
  /** Offered when the email can still be taken off, before anything reaches the server. */
  onUnlink?: () => void;
  onClose: () => void;
}) {
  const { user } = useSignedIn();
  const state = useAppState();
  const insets = useSafeAreaInsets();
  const [email, setEmail] = useState(initialEmail);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const typed = normalizedEmail(email);
  const taken = exclude.includes(typed);
  const valid = isValidEmail(typed) && typed !== initialEmail && !taken;

  const selfEmail = user.email ? normalizedEmail(user.email) : null;
  const known = useMemo(() => knownPeople(state, user.id, selfEmail), [state, user.id, selfEmail]);
  const q = email.trim().toLowerCase();
  const suggestions = known
    .filter((k) => !exclude.includes(k.email) && k.email !== typed)
    .filter((k) => !q || k.email.includes(q) || k.displayName.toLowerCase().includes(q))
    .sort((x, y) => nameMatchScore(y.displayName, name) - nameMatchScore(x.displayName, name))
    .slice(0, 4);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await onSave(typed);
      haptics.success();
      onClose();
    } catch (e) {
      haptics.error();
      setError(onlineMessage(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <KeyboardAvoidingView style={styles.backdrop} behavior={Platform.OS === "ios" ? "padding" : "height"}>
        <Pressable style={[styles.dismiss, { minHeight: insets.top + 24 }]} accessibilityLabel="Close" onPress={onClose} />
        <ScrollView style={styles.sheet} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          <Text style={styles.title}>{name}'s email</Text>
          <Text style={styles.body}>Pick a friend or type their email. They join when they open tab-it signed in with it.</Text>
          <Field
            value={email}
            onChangeText={(t) => {
              setEmail(t);
              setError(null);
            }}
            placeholder="name@example.com"
            autoFocus
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="email-address"
            onSubmitEditing={() => valid && save()}
            error={error ?? (taken ? "Someone in this trip already has that email." : null)}
          />
          {suggestions.length > 0 && (
            <View style={styles.suggestions}>
              {suggestions.map((k, i) => (
                <View key={k.email}>
                  {i > 0 && <Divider inset={62} />}
                  <PersonRow
                    person={k}
                    trailing={<Icon name="arrow-up-circle-outline" size={22} color={colors.accent} />}
                    label={`Use ${k.displayName}'s email`}
                    onPress={() => {
                      haptics.light();
                      setEmail(k.email);
                      setError(null);
                    }}
                  />
                </View>
              ))}
            </View>
          )}
          <View style={styles.buttons}>
            <Button title="Cancel" variant="secondary" onPress={onClose} style={{ flex: 1 }} />
            <Button title="Save email" onPress={save} disabled={!valid} loading={busy} style={{ flex: 1 }} />
          </View>
          {onUnlink && initialEmail !== "" && (
            <Button
              title="Remove email"
              variant="destructive"
              onPress={() => {
                onUnlink();
                onClose();
              }}
            />
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay },
  dismiss: { flex: 1 },
  // On a short screen the sheet scrolls, so nothing is left behind the keyboard.
  sheet: {
    flexGrow: 0,
    flexShrink: 1,
    backgroundColor: colors.bg,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    borderTopWidth: 1,
    borderColor: colors.cardBorder,
  },
  title: { fontSize: 17, fontWeight: "600", color: colors.text },
  body: { fontSize: 12.5, color: colors.textSecondary, marginTop: 1 },
  content: { padding: 20, paddingBottom: 34, gap: 12 },
  suggestions: {
    borderRadius: radius.control,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.cardBorder,
    overflow: "hidden",
  },
  buttons: { flexDirection: "row", gap: 10 },
});
