import { Platform, type TextStyle } from "react-native";

// Sage palette. design/mockups/v1.html is the source of truth for these values.
export const colors = {
  accent: "#6F9866",
  accentStrong: "#4F7549",
  accentSoft: "rgba(111,152,102,0.25)",
  accentTint: "#EEF2E7",
  accentGlow: "rgba(143,178,130,0.35)",

  bg: "#FAF7F0",
  surface: "#FFFFFF",
  surface2: "#F1ECE2",

  text: "#28281F",
  textSecondary: "#777267",
  textTertiary: "#A39E92",

  cardBorder: "rgba(60,50,30,0.06)",
  rowDivider: "rgba(60,50,30,0.07)",
  shadow: "rgba(50,60,40,0.06)",
  warning: "#B16D3F",
  danger: "#B5482F",
  segmentedBg: "rgba(60,50,30,0.06)",
  iconBg: "#F1ECE2",
  tabBarBg: "rgba(250,247,240,0.92)",
  tabBarBorder: "rgba(60,50,30,0.08)",
  owed: "#4F7549",
  owe: "#B16D3F",
  settle: "#6B8DA6",
  overlay: "rgba(40,40,31,0.35)",
} as const;

export const avatarTones = {
  terracotta: "#B97047",
  sage: "#859E62",
  sand: "#B98B59",
  slate: "#6B8DA6",
} as const;

export type AvatarTone = keyof typeof avatarTones;

export const categoryTones: Record<string, string> = {
  "00000001-0000-0000-0000-000000000000": "#B97047",
  "00000002-0000-0000-0000-000000000000": "#6B8DA6",
  "00000003-0000-0000-0000-000000000000": "#8B6B96",
  "00000004-0000-0000-0000-000000000000": "#C97A6B",
  "00000005-0000-0000-0000-000000000000": "#B98B59",
  "00000006-0000-0000-0000-000000000000": "#859E62",
};

export const radius = { card: 14, control: 10, pill: 999 } as const;

const tabular: TextStyle = { fontVariant: ["tabular-nums"] };

export const type = {
  largeTitle: { fontSize: 30, fontWeight: "700", letterSpacing: -0.75, color: colors.text },
  title: { fontSize: 20, fontWeight: "700", letterSpacing: -0.3, color: colors.text },
  sectionHeader: { fontSize: 11, fontWeight: "600", letterSpacing: 1.32, color: colors.textSecondary, textTransform: "uppercase" },
  body: { fontSize: 15, color: colors.text },
  bodyStrong: { fontSize: 15, fontWeight: "600", color: colors.text },
  rowTitle: { fontSize: 15, fontWeight: "500", color: colors.text },
  meta: { fontSize: 12.5, color: colors.textSecondary },
  small: { fontSize: 13, color: colors.textSecondary },
  amount: { fontSize: 15, fontWeight: "600", color: colors.text, ...tabular },
  balanceAmount: { fontSize: 34, fontWeight: "700", letterSpacing: -0.8, ...tabular },
  amountEntry: { fontSize: 52, fontWeight: "300", color: colors.text, ...tabular },
  label: { fontSize: 11, fontWeight: "600", letterSpacing: 1.2, color: colors.textSecondary, textTransform: "uppercase" },
} satisfies Record<string, TextStyle>;

export const shadow = Platform.select({
  ios: { shadowColor: "#323C28", shadowOpacity: 0.06, shadowRadius: 2, shadowOffset: { width: 0, height: 1 } },
  default: { elevation: 1 },
});

export const fabShadow = Platform.select({
  ios: { shadowColor: "#000", shadowOpacity: 0.22, shadowRadius: 10, shadowOffset: { width: 0, height: 6 } },
  default: { elevation: 6 },
});

/** Horizontal page margin shared by cards and headers. */
export const PAGE = 18;
