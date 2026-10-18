import Ionicons from "@expo/vector-icons/Ionicons";
import type { ComponentProps, ComponentRef, ReactNode, Ref } from "react";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import {
  ActivityIndicator,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type StyleProp,
  type TextInputProps,
  type TextStyle,
  type ViewStyle,
} from "react-native";

import { haptics } from "./haptics";
import { colors, fabShadow, PAGE, radius, shadow, type } from "./theme";

export type IconName = ComponentProps<typeof Ionicons>["name"];

export function Icon({
  name,
  size = 20,
  color = colors.text,
  style,
}: {
  name: IconName;
  size?: number;
  color?: string;
  style?: StyleProp<TextStyle>;
}) {
  return <Ionicons name={name} size={size} color={color} style={style} />;
}

export function LargeTitle({ title, right }: { title: string; right?: ReactNode }) {
  return (
    <View style={styles.largeTitleRow}>
      <Text style={type.largeTitle} numberOfLines={2} accessibilityRole="header">
        {title}
      </Text>
      {right}
    </View>
  );
}

export function SectionHeader({ title, right, first }: { title: string; right?: ReactNode; first?: boolean }) {
  return (
    <View style={[styles.sectionHeader, first && { paddingTop: 6 }]}>
      <Text style={type.sectionHeader} accessibilityRole="header">
        {title}
      </Text>
      {right}
    </View>
  );
}

export function Card({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function Divider({ inset = 0 }: { inset?: number }) {
  return <View style={[styles.divider, { marginLeft: inset }]} />;
}

export function Row({
  title,
  subtitle,
  left,
  right,
  value,
  onPress,
  onLongPress,
  chevron,
  destructive,
  disabled,
  accessibilityLabel,
  titleLines = 1,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  left?: ReactNode;
  right?: ReactNode;
  value?: string;
  onPress?: () => void;
  onLongPress?: () => void;
  chevron?: boolean;
  destructive?: boolean;
  disabled?: boolean;
  accessibilityLabel?: string;
  titleLines?: number;
}) {
  const body = (
    <>
      {left}
      <View style={styles.rowText}>
        {typeof title === "string" ? (
          <Text style={[type.rowTitle, destructive && { color: colors.danger }]} numberOfLines={titleLines}>
            {title}
          </Text>
        ) : (
          title
        )}
        {typeof subtitle === "string" ? (
          <Text style={[type.meta, { marginTop: 2 }]} numberOfLines={1}>
            {subtitle}
          </Text>
        ) : (
          subtitle
        )}
      </View>
      {value !== undefined && (
        <Text style={[type.body, { color: colors.textSecondary }]} numberOfLines={1}>
          {value}
        </Text>
      )}
      {right}
      {chevron && <Icon name="chevron-forward" size={16} color={colors.textTertiary} />}
    </>
  );
  if (!onPress && !onLongPress) return <View style={styles.row}>{body}</View>;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      disabled={disabled}
      onPress={onPress}
      onLongPress={onLongPress}
      android_ripple={{ color: colors.rowDivider }}
      style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surface2 }, disabled && { opacity: 0.5 }]}
    >
      {body}
    </Pressable>
  );
}

type ButtonVariant = "primary" | "secondary" | "plain" | "destructive";

export function Button({
  title,
  onPress,
  variant = "primary",
  icon,
  loading,
  disabled,
  style,
  accessibilityLabel,
}: {
  title: string;
  onPress: () => void;
  variant?: ButtonVariant;
  icon?: IconName;
  loading?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  accessibilityLabel?: string;
}) {
  const palette = {
    primary: { bg: colors.accent, fg: "#fff" },
    secondary: { bg: colors.surface, fg: colors.text },
    plain: { bg: "transparent", fg: colors.accentStrong },
    destructive: { bg: "transparent", fg: colors.danger },
  }[variant];
  const inactive = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      accessibilityState={{ disabled: !!inactive, busy: !!loading }}
      disabled={inactive}
      onPress={() => {
        if (variant === "primary") haptics.light();
        onPress();
      }}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: palette.bg },
        variant === "secondary" && styles.buttonOutline,
        pressed && { opacity: 0.75, transform: [{ scale: 0.98 }] },
        disabled && !loading && { opacity: 0.45 },
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={palette.fg} />
      ) : (
        <View style={styles.buttonInner}>
          {icon && <Icon name={icon} size={18} color={palette.fg} />}
          <Text style={[styles.buttonText, { color: palette.fg }]}>{title}</Text>
        </View>
      )}
    </Pressable>
  );
}

export function IconButton({
  icon,
  onPress,
  label,
  color = colors.accentStrong,
  size = 22,
  disabled,
}: {
  icon: IconName;
  onPress: () => void;
  label: string;
  color?: string;
  size?: number;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      hitSlop={10}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [styles.iconButton, (pressed || disabled) && { opacity: 0.5 }]}
    >
      <Icon name={icon} size={size} color={color} />
    </Pressable>
  );
}

/**
 * Space from the bottom of a tab screen to just above its tab bar. On iOS the
 * floating tab bar overlaps the screen and the screen's bottom safe area
 * already reaches its top edge; on Android the tab bar sits below the screen.
 */
export function useTabBarClearance(): number {
  const insets = useSafeAreaInsets();
  return Platform.OS === "ios" ? insets.bottom : 16;
}

export function Fab({ label, icon = "add", onPress, bottom }: { label?: string; icon?: IconName; onPress: () => void; bottom?: number }) {
  const insets = useSafeAreaInsets();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label ?? "Add"}
      onPress={() => {
        haptics.medium();
        onPress();
      }}
      style={({ pressed }) => [
        styles.fab,
        { bottom: bottom ?? insets.bottom + 16 },
        label ? styles.fabWide : styles.fabRound,
        pressed && { transform: [{ scale: 0.95 }] },
      ]}
    >
      <Icon name={icon} size={label ? 20 : 26} color="#fff" />
      {label && <Text style={styles.fabText}>{label}</Text>}
    </Pressable>
  );
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  style,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
  style?: StyleProp<ViewStyle>;
}) {
  return (
    <View style={[styles.segmented, style]} accessibilityRole="tablist">
      {options.map((o) => {
        const active = o.value === value;
        return (
          <Pressable
            key={o.value}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            onPress={() => {
              if (!active) {
                haptics.selection();
                onChange(o.value);
              }
            }}
            style={[styles.segment, active && styles.segmentActive]}
          >
            <Text style={[styles.segmentText, active && styles.segmentTextActive]} numberOfLines={1}>
              {o.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Chip({ label, selected, onPress, icon }: { label: string; selected?: boolean; onPress?: () => void; icon?: ReactNode }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected: !!selected }}
      onPress={() => {
        haptics.selection();
        onPress?.();
      }}
      style={({ pressed }) => [styles.chip, selected && styles.chipSelected, pressed && { opacity: 0.7 }]}
    >
      {icon}
      <Text style={[styles.chipText, selected && { color: colors.accentStrong }]} numberOfLines={1}>
        {label}
      </Text>
    </Pressable>
  );
}

export function EmptyState({ icon, title, message, action }: { icon: IconName; title: string; message?: string; action?: ReactNode }) {
  return (
    <View style={styles.empty}>
      <View style={styles.emptyIcon}>
        <Icon name={icon} size={28} color={colors.accent} />
      </View>
      <Text style={[type.bodyStrong, { textAlign: "center" }]}>{title}</Text>
      {message && <Text style={[type.small, { textAlign: "center", marginTop: 6, lineHeight: 19 }]}>{message}</Text>}
      {action && <View style={{ marginTop: 18, alignSelf: "stretch" }}>{action}</View>}
    </View>
  );
}

export function Field({
  label,
  error,
  hint,
  style,
  ref,
  ...props
}: TextInputProps & { label?: string; error?: string | null; hint?: string; ref?: Ref<ComponentRef<typeof TextInput>> }) {
  return (
    <View style={{ gap: 6 }}>
      {label && <Text style={type.label}>{label}</Text>}
      <TextInput
        ref={ref}
        placeholderTextColor={colors.textTertiary}
        selectionColor={colors.accent}
        style={[styles.field, !!error && { borderColor: colors.danger }, style]}
        {...props}
      />
      {error ? <Text style={[type.small, { color: colors.danger }]}>{error}</Text> : hint ? <Text style={type.small}>{hint}</Text> : null}
    </View>
  );
}

export function Banner({
  tone = "info",
  text,
  action,
}: {
  tone?: "info" | "warning";
  text: string;
  action?: { label: string; onPress: () => void };
}) {
  const warning = tone === "warning";
  return (
    <View style={[styles.banner, warning && { backgroundColor: "#F6E9DE" }]}>
      <Icon name={warning ? "alert-circle" : "cloud-offline-outline"} size={18} color={warning ? colors.warning : colors.textSecondary} />
      <Text style={[type.small, { flex: 1, color: warning ? colors.warning : colors.textSecondary }]}>{text}</Text>
      {action && (
        <Pressable onPress={action.onPress} hitSlop={8} accessibilityRole="button">
          <Text style={[type.small, { color: colors.accentStrong, fontWeight: "600" }]}>{action.label}</Text>
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  largeTitleRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: PAGE + 4,
    paddingTop: 14,
    paddingBottom: 10,
    gap: 12,
  },
  sectionHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: PAGE + 8,
    paddingTop: 22,
    paddingBottom: 8,
  },
  card: {
    marginHorizontal: PAGE,
    marginBottom: 14,
    backgroundColor: colors.surface,
    borderRadius: radius.card,
    borderWidth: 1,
    borderColor: colors.cardBorder,
    overflow: "hidden",
    ...shadow,
  },
  divider: { height: StyleSheet.hairlineWidth * 2, backgroundColor: colors.rowDivider },
  row: { flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 13, gap: 12, minHeight: 52 },
  rowText: { flex: 1, minWidth: 0 },
  button: { minHeight: 50, borderRadius: radius.card, alignItems: "center", justifyContent: "center", paddingHorizontal: 18 },
  buttonOutline: { borderWidth: 1, borderColor: colors.cardBorder, ...shadow },
  buttonInner: { flexDirection: "row", alignItems: "center", gap: 8 },
  buttonText: { fontSize: 16, fontWeight: "600" },
  iconButton: { padding: 4 },
  fab: {
    position: "absolute",
    right: PAGE,
    bottom: 20,
    backgroundColor: colors.accent,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    borderRadius: radius.pill,
    ...fabShadow,
  },
  fabWide: { height: 52, paddingHorizontal: 20 },
  fabRound: { width: 56, height: 56 },
  fabText: { color: "#fff", fontSize: 15, fontWeight: "600" },
  segmented: {
    flexDirection: "row",
    padding: 3,
    borderRadius: radius.control,
    backgroundColor: colors.segmentedBg,
    marginHorizontal: PAGE,
  },
  segment: { flex: 1, paddingVertical: 8, alignItems: "center", borderRadius: 7 },
  segmentActive: { backgroundColor: colors.surface, ...shadow },
  segmentText: { fontSize: 13, fontWeight: "500", color: colors.textSecondary },
  segmentTextActive: { color: colors.text, fontWeight: "600" },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: radius.pill,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.cardBorder,
  },
  chipSelected: { backgroundColor: colors.accentTint, borderColor: colors.accentSoft },
  chipText: { fontSize: 13, fontWeight: "500", color: colors.text },
  empty: { alignItems: "center", paddingHorizontal: 40, paddingVertical: 48 },
  emptyIcon: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: colors.accentTint,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 14,
  },
  field: {
    minHeight: 50,
    borderRadius: radius.control,
    borderWidth: 1,
    borderColor: colors.cardBorder,
    backgroundColor: colors.surface,
    paddingHorizontal: 14,
    fontSize: 16,
    color: colors.text,
  },
  banner: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    marginHorizontal: PAGE,
    marginBottom: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: radius.control,
    backgroundColor: colors.surface2,
  },
});

/** A text button for navigation bars (Cancel, Save). */
export function HeaderButton({
  title,
  onPress,
  disabled,
  bold,
  loading,
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  bold?: boolean;
  loading?: boolean;
}) {
  if (loading) return <ActivityIndicator color={colors.accent} />;
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      hitSlop={10}
      style={({ pressed }) => [{ paddingHorizontal: 4 }, pressed && { opacity: 0.5 }]}
    >
      <Text
        style={{
          fontSize: 16,
          fontWeight: bold ? "600" : "400",
          color: disabled ? colors.textTertiary : bold ? colors.accentStrong : colors.text,
        }}
      >
        {title}
      </Text>
    </Pressable>
  );
}
