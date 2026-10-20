import { useMemo, useState, type ReactNode } from "react";
import { Pressable, StyleSheet, Text, TextInput, View } from "react-native";

import { knownPeople, type KnownPerson } from "@/data/selectors";
import { pickContactEmail } from "@/features/people/contacts";
import { displayNameFromEmail } from "@/features/people/email";
import { useAppState, useSignedIn } from "@/data/session";
import { isValidEmail, normalizedEmail } from "@/domain";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Card, Divider, Icon, SectionHeader } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

export interface PickedPerson {
  email: string;
  displayName: string;
  /** Known people who have joined somewhere keep their account's avatar colour. */
  userId?: string | null;
}

/**
 * Pick people by searching everyone you've shared a trip with, or by typing
 * an email. `exclude` hides people already in the trip.
 */
export function PeoplePicker({
  selected,
  onChange,
  exclude = [],
  autoFocus,
}: {
  selected: PickedPerson[];
  onChange: (people: PickedPerson[]) => void;
  exclude?: string[];
  autoFocus?: boolean;
}) {
  const { user } = useSignedIn();
  const state = useAppState();
  const [query, setQuery] = useState("");
  const selfEmail = user.email ? normalizedEmail(user.email) : null;

  const known = useMemo(() => knownPeople(state, user.id, selfEmail), [state, user.id, selfEmail]);
  const chosen = new Set([...selected.map((p) => p.email), ...exclude]);
  const q = query.trim().toLowerCase();
  const results = known
    .filter((p) => !chosen.has(p.email))
    .filter((p) => !q || p.email.includes(q) || p.displayName.toLowerCase().includes(q))
    .slice(0, q ? 12 : 8);
  const typedEmail = normalizedEmail(query);
  const canInvite =
    isValidEmail(typedEmail) && typedEmail !== selfEmail && !chosen.has(typedEmail) && !known.some((k) => k.email === typedEmail);

  function add(person: PickedPerson) {
    haptics.light();
    onChange([...selected, person]);
    setQuery("");
  }

  return (
    <View>
      <View style={styles.search}>
        <Icon name="search" size={16} color={colors.textSecondary} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search names or type an email"
          placeholderTextColor={colors.textTertiary}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
          autoFocus={autoFocus}
          returnKeyType="done"
          onSubmitEditing={() => canInvite && add({ email: typedEmail, displayName: displayNameFromEmail(typedEmail) })}
          style={styles.input}
          accessibilityLabel="Search people or enter an email"
        />
      </View>

      <Pressable
        accessibilityRole="button"
        onPress={async () => {
          const picked = await pickContactEmail().catch(() => null);
          if (!picked) return;
          if (picked.email === selfEmail || chosen.has(picked.email)) return;
          add(picked);
        }}
        style={({ pressed }) => [styles.contacts, pressed && { opacity: 0.6 }]}
      >
        <Icon name="person-circle-outline" size={18} color={colors.accentStrong} />
        <Text style={styles.contactsText}>Choose from contacts</Text>
      </Pressable>

      {selected.length > 0 && (
        <>
          <SectionHeader title={`Adding ${selected.length}`} />
          <Card>
            {selected.map((p, i) => (
              <View key={p.email}>
                {i > 0 && <Divider inset={62} />}
                <PersonRow
                  person={p}
                  trailing={<Icon name="close-circle" size={22} color={colors.textTertiary} />}
                  label={`Remove ${p.displayName}`}
                  onPress={() => onChange(selected.filter((s) => s.email !== p.email))}
                />
              </View>
            ))}
          </Card>
        </>
      )}

      {(results.length > 0 || canInvite) && (
        <>
          <SectionHeader title={q ? "Results" : "People you split with"} />
          <Card>
            {canInvite && (
              <PersonRow
                person={{ email: typedEmail, displayName: `Add ${typedEmail}` }}
                invite
                trailing={<Icon name="add-circle" size={22} color={colors.accent} />}
                label={`Add ${typedEmail}`}
                onPress={() => add({ email: typedEmail, displayName: displayNameFromEmail(typedEmail) })}
              />
            )}
            {results.map((p: KnownPerson, i) => (
              <View key={p.email}>
                {(i > 0 || canInvite) && <Divider inset={62} />}
                <PersonRow
                  person={p}
                  trailing={<Icon name="add-circle-outline" size={22} color={colors.accent} />}
                  label={`Add ${p.displayName}`}
                  onPress={() => add({ email: p.email, displayName: p.displayName, userId: p.userId })}
                />
              </View>
            ))}
          </Card>
        </>
      )}

      {results.length === 0 && !canInvite && selected.length === 0 && (
        <Text style={styles.hint}>
          {q
            ? "Type their full email address to add someone new."
            : "Type an email to add someone. People you've split with before show up here."}
        </Text>
      )}
    </View>
  );
}

export function PersonRow({
  person,
  trailing,
  onPress,
  label,
  invite,
}: {
  person: PickedPerson;
  trailing: ReactNode;
  onPress: () => void;
  label: string;
  invite?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surface2 }]}
    >
      {invite ? (
        <View style={styles.inviteIcon}>
          <Icon name="mail-outline" size={16} color={colors.textSecondary} />
        </View>
      ) : (
        <Avatar person={{ id: person.email, name: person.displayName, userId: person.userId, email: person.email }} size={34} ring={0} />
      )}
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={[styles.name, invite && { color: colors.accentStrong, fontWeight: "600" }]} numberOfLines={1}>
          {person.displayName}
        </Text>
        {!invite && (
          <Text style={styles.email} numberOfLines={1} ellipsizeMode="middle">
            {person.email}
          </Text>
        )}
      </View>
      {trailing}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  search: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginHorizontal: PAGE,
    marginTop: 8,
    paddingHorizontal: 12,
    height: 44,
    borderRadius: radius.control,
    backgroundColor: colors.surface2,
  },
  input: { flex: 1, fontSize: 16, color: colors.text, paddingVertical: 0 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 15, paddingVertical: 11 },
  inviteIcon: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.surface2, alignItems: "center", justifyContent: "center" },
  name: { fontSize: 15, fontWeight: "500", color: colors.text },
  email: { fontSize: 12, color: colors.textSecondary, marginTop: 1 },
  contacts: { flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: PAGE + 4, paddingTop: 12, alignSelf: "flex-start" },
  contactsText: { fontSize: 14, fontWeight: "500", color: colors.accentStrong },
  hint: { fontSize: 13, color: colors.textSecondary, textAlign: "center", paddingHorizontal: 40, paddingTop: 28, lineHeight: 19 },
});
