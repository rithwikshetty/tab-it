import { Pressable, StyleSheet, Text, View } from "react-native";

import { avatarInitial, avatarTone, emailAvatarTone } from "@/domain";

import { haptics } from "./haptics";
import { avatarTones, colors } from "./theme";

export interface AvatarPerson {
  id: string;
  name: string;
  /** Pending people have no stable account yet; their colour follows the email. */
  email?: string | null;
  pending?: boolean;
}

export function toneFor(person: AvatarPerson): string {
  const tone = person.pending && person.email ? emailAvatarTone(person.email) : avatarTone(person.id);
  return avatarTones[tone];
}

export function Avatar({ person, size = 28, ring = 2 }: { person: AvatarPerson; size?: number; ring?: number }) {
  return (
    <View
      style={[
        styles.avatar,
        { width: size, height: size, borderRadius: size / 2, borderWidth: ring, backgroundColor: toneFor(person) },
      ]}
    >
      <Text style={[styles.initial, { fontSize: size >= 40 ? 16 : size >= 32 ? 13 : 11 }]} allowFontScaling={false}>
        {avatarInitial(person.name)}
      </Text>
    </View>
  );
}

export function AvatarGroup({
  people,
  size = 28,
  ring = 2,
  max = 5,
  onAdd,
}: {
  people: AvatarPerson[];
  size?: number;
  ring?: number;
  max?: number;
  onAdd?: () => void;
}) {
  const overflow = people.length > max ? people.length - (max - 1) : 0;
  const visible = overflow > 0 ? people.slice(0, max - 1) : people;
  return (
    <View style={styles.group}>
      <View style={styles.stack}>
        {visible.map((p, i) => (
          <View key={p.id} style={{ marginLeft: i === 0 ? 0 : -8 }}>
            <Avatar person={p} size={size} ring={ring} />
          </View>
        ))}
        {overflow > 0 && (
          <View
            style={[
              styles.avatar,
              { marginLeft: -8, width: size, height: size, borderRadius: size / 2, borderWidth: ring, backgroundColor: colors.surface2 },
            ]}
          >
            <Text style={[styles.initial, { color: colors.textSecondary, fontSize: size >= 34 ? 13 : 11 }]}>+{overflow}</Text>
          </View>
        )}
      </View>
      {onAdd && (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Add people"
          hitSlop={8}
          onPress={() => {
            haptics.light();
            onAdd();
          }}
          style={({ pressed }) => [
            styles.add,
            { width: size, height: size, borderRadius: size / 2, borderWidth: ring, opacity: pressed ? 0.6 : 1 },
          ]}
        >
          <Text style={[styles.addText, { fontSize: size >= 40 ? 20 : 15 }]}>+</Text>
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  avatar: { alignItems: "center", justifyContent: "center", borderColor: colors.surface },
  initial: { color: "#fff", fontWeight: "600" },
  group: { flexDirection: "row", alignItems: "center", gap: 5 },
  stack: { flexDirection: "row", alignItems: "center" },
  add: { alignItems: "center", justifyContent: "center", borderColor: colors.accentSoft, borderStyle: "dashed" },
  addText: { color: colors.accent, fontWeight: "400", marginTop: -1 },
});
