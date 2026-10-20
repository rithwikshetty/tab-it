import * as DocumentPicker from "expo-document-picker";
import { File } from "expo-file-system";
import { router, Stack } from "expo-router";
import { useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

import { importSplitwise } from "@/data/actions";
import { knownPeople } from "@/data/selectors";
import { useSignedIn } from "@/data/session";
import { bestSelfMatch, ImportParseError, normalizedEmail, parseSplitwise, suggestImportLinks, type ImportResult } from "@/domain";
import { PersonEmailSheet } from "@/features/people/email-sheet";
import { Avatar } from "@/ui/avatar";
import { haptics } from "@/ui/haptics";
import { Button, Card, Divider, Field, HeaderButton, Icon, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

const MAX_BYTES = 5 * 1024 * 1024;

function parseError(e: unknown): string {
  if (e instanceof ImportParseError) {
    if (e.code === "empty") return "That file is empty.";
    if (e.code === "noPeople") return "No people were found in that export.";
    return "That doesn't look like a Splitwise export. Use the spreadsheet (CSV) export from a group.";
  }
  return `Couldn't read that file. ${(e as Error)?.message ?? ""}`.trim();
}

export default function ImportSplitwise() {
  const ctx = useSignedIn();
  const [parsed, setParsed] = useState<ImportResult | null>(null);
  const [tripName, setTripName] = useState("");
  const [self, setSelf] = useState<string | null>(null);
  /** Imported name to the email it's added under. */
  const [links, setLinks] = useState<ReadonlyMap<string, string>>(new Map());
  const [linking, setLinking] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const selfEmail = ctx.user.email ? normalizedEmail(ctx.user.email) : null;
  const others = parsed ? parsed.people.filter((name) => name !== self) : [];

  function removeEmail(name: string) {
    setLinks((current) => {
      const next = new Map(current);
      next.delete(name);
      return next;
    });
  }

  async function choose() {
    setError(null);
    const result = await DocumentPicker.getDocumentAsync({
      type: ["text/csv", "text/comma-separated-values", "text/plain", "public.comma-separated-values-text", "*/*"],
      copyToCacheDirectory: true,
    });
    const asset = result.canceled ? null : result.assets[0];
    if (!asset) return;
    try {
      const file = new File(asset.uri);
      if ((file.size ?? 0) > MAX_BYTES) throw new Error("It's larger than 5 MB.");
      const data = parseSplitwise(await file.text());
      setParsed(data);
      setTripName((asset.name ?? "").replace(/\.[^.]+$/, "").trim() || "Imported trip");
      const me = bestSelfMatch(data.people, ctx.user.displayName);
      setSelf(me);
      setLinks(
        suggestImportLinks(
          data.people.filter((name) => name !== me),
          knownPeople(ctx.store.getState(), ctx.user.id, selfEmail),
        ),
      );
    } catch (e) {
      setError(parseError(e));
    }
  }

  async function run() {
    if (!parsed || !tripName.trim()) return;
    setImporting(true);
    try {
      const tripId = await importSplitwise(ctx, parsed, tripName.trim(), self, links);
      haptics.success();
      router.dismissAll();
      router.push({ pathname: "/trip/[id]", params: { id: tripId } });
    } catch (e) {
      setImporting(false);
      Alert.alert("Couldn't import", (e as Error).message);
    }
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen options={{ headerLeft: () => <HeaderButton title="Cancel" disabled={importing} onPress={() => router.back()} /> }} />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 48 }}>
        {!parsed ? (
          <View style={styles.intro}>
            <View style={styles.introIcon}>
              <Icon name="download-outline" size={28} color={colors.accentStrong} />
            </View>
            <Text style={styles.introTitle}>Bring a Splitwise group into tab-it</Text>
            <Text style={styles.introBody}>
              In Splitwise, open a group, choose Export as spreadsheet, and save the CSV. Then pick it here.
            </Text>
            <Button title="Choose CSV file" icon="document-outline" onPress={choose} style={{ alignSelf: "stretch", marginTop: 8 }} />
            {error && <Text style={styles.error}>{error}</Text>}
          </View>
        ) : (
          <>
            <View style={{ paddingHorizontal: PAGE, paddingTop: 16 }}>
              <Field label="Trip name" value={tripName} onChangeText={setTripName} maxLength={100} />
            </View>
            <SectionHeader title="Which one is you?" />
            <Card>
              {[...parsed.people, null].map((name, i) => (
                <View key={name ?? "none"}>
                  {i > 0 && <Divider inset={50} />}
                  <Pressable
                    accessibilityRole="radio"
                    accessibilityState={{ checked: self === name }}
                    onPress={() => {
                      setSelf(name);
                      // You're added under your own email, never a friend's.
                      if (name !== null) removeEmail(name);
                    }}
                    style={styles.option}
                  >
                    <Icon
                      name={self === name ? "radio-button-on" : "radio-button-off"}
                      size={22}
                      color={self === name ? colors.accent : colors.textTertiary}
                    />
                    <Text style={[styles.optionText, name === null && { color: colors.textSecondary }]}>
                      {name ?? "I'm not in this group"}
                    </Text>
                  </Pressable>
                </View>
              ))}
            </Card>
            {others.length > 0 && (
              <>
                <SectionHeader title="Who's everyone else?" />
                <Card>
                  {others.map((name, i) => (
                    <View key={name}>
                      {i > 0 && <Divider inset={58} />}
                      <Row
                        left={<Avatar person={{ id: name, name, email: links.get(name) ?? null }} size={30} ring={0} />}
                        title={name}
                        subtitle={links.get(name) ?? "No email yet"}
                        accessibilityLabel={links.has(name) ? `${name}, ${links.get(name)}` : `Add ${name}'s email`}
                        onPress={() => setLinking(name)}
                        chevron
                      />
                    </View>
                  ))}
                </Card>
              </>
            )}
            <Card style={{ padding: 16, gap: 4 }}>
              <Text style={styles.summary}>
                {parsed.people.length} {parsed.people.length === 1 ? "person" : "people"} · {parsed.expenses.length}{" "}
                {parsed.expenses.length === 1 ? "expense" : "expenses"} · {parsed.settlements.length}{" "}
                {parsed.settlements.length === 1 ? "payment" : "payments"}
              </Text>
              <Text style={styles.small}>
                People with an email join when they open tab-it signed in with it. Anyone without one is added by name, and you can add
                their email later from the trip's People screen.
              </Text>
            </Card>
            {parsed.warnings.length > 0 && (
              <>
                <SectionHeader title={`Notes (${parsed.warnings.length})`} />
                <Card style={{ padding: 14, gap: 6 }}>
                  {parsed.warnings.slice(0, 50).map((w, i) => (
                    <Text key={i} style={styles.small}>
                      Line {w.line}: {w.message}
                    </Text>
                  ))}
                </Card>
              </>
            )}
            <View style={{ paddingHorizontal: PAGE, gap: 8, marginTop: 6 }}>
              <Button
                title={tripName.trim() ? `Import ${tripName.trim()}` : "Import trip"}
                onPress={run}
                loading={importing}
                disabled={!tripName.trim()}
              />
              <Button title="Choose another file" variant="plain" onPress={choose} disabled={importing} />
            </View>
          </>
        )}
      </ScrollView>
      {linking !== null && (
        <PersonEmailSheet
          name={linking}
          initialEmail={links.get(linking) ?? ""}
          exclude={[...(selfEmail ? [selfEmail] : []), ...others.flatMap((name) => (name !== linking && links.get(name)) || [])]}
          onSave={(email) => setLinks((current) => new Map(current).set(linking, email))}
          onUnlink={() => removeEmail(linking)}
          onClose={() => setLinking(null)}
        />
      )}
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  intro: { alignItems: "center", paddingHorizontal: 28, paddingTop: 40, gap: 10 },
  introIcon: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: colors.accentTint,
    alignItems: "center",
    justifyContent: "center",
  },
  introTitle: { fontSize: 19, fontWeight: "600", color: colors.text, textAlign: "center" },
  introBody: { fontSize: 14, color: colors.textSecondary, textAlign: "center", lineHeight: 20 },
  error: { fontSize: 13, color: colors.danger, textAlign: "center", marginTop: 6 },
  option: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 13 },
  optionText: { fontSize: 15, color: colors.text, flex: 1 },
  summary: { fontSize: 15, fontWeight: "600", color: colors.text },
  small: { fontSize: 13, color: colors.textSecondary, lineHeight: 18 },
});
