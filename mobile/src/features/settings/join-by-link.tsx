import { router } from "expo-router";
import { useState } from "react";
import { Modal, StyleSheet, Text, View } from "react-native";

import { isInviteToken } from "@/data/invites";
import { inviteErrorMessage, joinTripWithInvite } from "@/data/online";
import { useSignedIn } from "@/data/session";
import { haptics } from "@/ui/haptics";
import { Button, Field } from "@/ui/primitives";
import { colors } from "@/ui/theme";

/** Accepts a pasted tab-it.app/join link or the bare 32-character token. */
export function inviteTokenFrom(input: string): string | null {
  const text = input.trim();
  const match = /^(?:https?:\/\/(?:www\.)?tab-it\.app\/join\/|com\.rithwikshetty\.tab:\/\/join\/)?([0-9a-fA-F]{32})\/?$/.exec(text);
  const token = match?.[1]?.toLowerCase() ?? null;
  return token && isInviteToken(token) ? token : null;
}

export function JoinByLink({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const ctx = useSignedIn();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const token = inviteTokenFrom(text);

  async function join() {
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      const { tripId } = await joinTripWithInvite(ctx, token);
      haptics.success();
      setText("");
      onClose();
      router.push({ pathname: "/trip/[id]", params: { id: tripId } });
    } catch (e) {
      haptics.error();
      setError(inviteErrorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <View style={styles.card}>
          <Text style={styles.title}>Join a trip</Text>
          <Text style={styles.body}>Paste the invite link someone sent you.</Text>
          <Field
            value={text}
            onChangeText={(t) => {
              setText(t);
              setError(null);
            }}
            placeholder="https://tab-it.app/join/…"
            autoCapitalize="none"
            autoCorrect={false}
            autoFocus
            error={error ?? (text.trim() && !token ? "That doesn't look like a tab-it invite link." : null)}
          />
          <View style={styles.buttons}>
            <Button title="Cancel" variant="secondary" onPress={onClose} style={{ flex: 1 }} />
            <Button title="Join" onPress={join} disabled={!token} loading={busy} style={{ flex: 1 }} />
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: "center", padding: 24 },
  card: { backgroundColor: colors.bg, borderRadius: 18, padding: 20, gap: 12 },
  title: { fontSize: 18, fontWeight: "600", color: colors.text },
  body: { fontSize: 14, color: colors.textSecondary },
  buttons: { flexDirection: "row", gap: 10, marginTop: 4 },
});
