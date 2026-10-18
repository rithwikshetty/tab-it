import { useMemo, useState } from "react";
import { FlatList, Modal, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { searchCurrencies, supportedCurrencies } from "@/domain";
import { haptics } from "@/ui/haptics";
import { HeaderButton, Icon } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

/** Searchable currency list in a sheet. Picking a row commits and closes. */
export function CurrencyPicker({
  visible,
  value,
  onPick,
  onClose,
}: {
  visible: boolean;
  value: string;
  onPick: (code: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const list = useMemo(() => (query.trim() ? searchCurrencies(query) : supportedCurrencies), [query]);
  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={styles.fill} edges={["bottom"]}>
        <View style={styles.header}>
          <Text style={styles.title}>Currency</Text>
          <HeaderButton title="Done" bold onPress={onClose} />
        </View>
        <View style={styles.search}>
          <Icon name="search" size={16} color={colors.textSecondary} />
          <TextInput
            value={query}
            onChangeText={setQuery}
            placeholder="Search code or name"
            placeholderTextColor={colors.textTertiary}
            autoCorrect={false}
            autoCapitalize="none"
            style={styles.input}
          />
        </View>
        <FlatList
          data={list}
          keyExtractor={(c) => c.code}
          keyboardShouldPersistTaps="handled"
          initialNumToRender={20}
          renderItem={({ item }) => (
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ selected: item.code === value }}
              onPress={() => {
                haptics.selection();
                onPick(item.code);
                setQuery("");
                onClose();
              }}
              style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surface2 }]}
            >
              <Text style={styles.symbol}>{item.symbol}</Text>
              <View style={{ flex: 1 }}>
                <Text style={styles.code}>{item.code}</Text>
                <Text style={styles.name} numberOfLines={1}>
                  {item.name}
                </Text>
              </View>
              {item.code === value && <Icon name="checkmark" size={20} color={colors.accentStrong} />}
            </Pressable>
          )}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
        />
      </SafeAreaView>
    </Modal>
  );
}

/** The tappable currency pill shown next to an amount. */
export function CurrencyPill({ code, onPress }: { code: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Currency ${code}. Change`}
      onPress={onPress}
      style={({ pressed }) => [styles.pill, pressed && { opacity: 0.7 }]}
    >
      <Text style={styles.pillText}>{code}</Text>
      <Icon name="chevron-down" size={12} color={colors.accentStrong} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: PAGE,
    paddingTop: 18,
    paddingBottom: 8,
  },
  title: { fontSize: 18, fontWeight: "600", color: colors.text },
  search: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginHorizontal: PAGE,
    marginBottom: 8,
    paddingHorizontal: 12,
    height: 42,
    borderRadius: radius.control,
    backgroundColor: colors.surface2,
  },
  input: { flex: 1, fontSize: 16, color: colors.text, paddingVertical: 0 },
  row: { flexDirection: "row", alignItems: "center", gap: 14, paddingHorizontal: PAGE + 4, paddingVertical: 12 },
  symbol: { width: 40, fontSize: 17, fontWeight: "600", color: colors.text, textAlign: "center" },
  code: { fontSize: 15, fontWeight: "600", color: colors.text },
  name: { fontSize: 13, color: colors.textSecondary },
  sep: { height: StyleSheet.hairlineWidth, backgroundColor: colors.rowDivider, marginLeft: PAGE + 58 },
  pill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: radius.pill,
    backgroundColor: colors.accentTint,
    borderWidth: 1,
    borderColor: colors.accentSoft,
  },
  pillText: { fontSize: 14, fontWeight: "600", color: colors.accentStrong, fontVariant: ["tabular-nums"] },
});
