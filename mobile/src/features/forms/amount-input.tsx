import type { ComponentRef, Ref } from "react";
import { StyleSheet, Text, TextInput, View } from "react-native";

import { displayMetadata, plainAmountString, sanitizeAmountInput } from "@/domain";
import { colors } from "@/ui/theme";

/**
 * The large amount field. Accepts digits with either "." or "," as the
 * decimal mark and stops at the currency's minor-unit digits.
 */
export function AmountInput({
  value,
  currency,
  onChange,
  autoFocus,
  ref,
  tone = colors.text,
}: {
  value: string;
  currency: string;
  onChange: (text: string) => void;
  autoFocus?: boolean;
  ref?: Ref<ComponentRef<typeof TextInput>>;
  tone?: string;
}) {
  const symbol = displayMetadata(currency).symbol;
  return (
    <View style={styles.row}>
      <Text style={[styles.symbol, { color: tone }]} numberOfLines={1}>
        {symbol}
      </Text>
      <TextInput
        ref={ref}
        value={value}
        onChangeText={(text) => onChange(sanitizeAmountInput(text, currency))}
        placeholder={plainAmountString(0n, currency)}
        placeholderTextColor={colors.textTertiary}
        keyboardType="decimal-pad"
        autoFocus={autoFocus}
        selectionColor={colors.accent}
        style={[styles.input, { color: tone }]}
        accessibilityLabel={`Amount in ${currency}`}
        maxLength={16}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 6, paddingVertical: 4 },
  symbol: { fontSize: 34, fontWeight: "300", maxWidth: 110 },
  input: { fontSize: 52, fontWeight: "300", minWidth: 80, textAlign: "left", fontVariant: ["tabular-nums"], paddingVertical: 0 },
});
