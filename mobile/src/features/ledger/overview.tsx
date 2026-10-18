import { useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import Svg, { Circle } from "react-native-svg";

import type { resolveOverview } from "@/domain";
import { CategoryIcon } from "@/ui/category-icon";
import { Card, Chip, Divider } from "@/ui/primitives";
import { colors, PAGE } from "@/ui/theme";

type Overview = ReturnType<typeof resolveOverview>;
type Page = Overview["pages"][number];

/** Per-trip spend: total and your share, per person, by category. One currency at a time. */
export function OverviewSection({ overview, categoryIcon }: { overview: Overview; categoryIcon: (id: string | null) => string | null }) {
  const [index, setIndex] = useState(0);
  const page = overview.pages[Math.min(index, overview.pages.length - 1)];
  if (!page) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyTitle}>Nothing spent yet</Text>
        <Text style={styles.muted}>The overview fills in as you add expenses.</Text>
      </View>
    );
  }
  return (
    <View>
      {overview.currencies.length > 1 && (
        <View style={styles.currencies}>
          {overview.currencies.map((c, i) => (
            <Chip key={c} label={c} selected={i === index} onPress={() => setIndex(i)} />
          ))}
        </View>
      )}
      <Summary page={page} />
      {page.people.length > 0 && (
        <Card>
          <Text style={styles.eyebrow}>Per person · share and paid</Text>
          {page.people.map((p, i) => (
            <View key={p.id}>
              {i > 0 && <Divider inset={16} />}
              <View style={styles.personRow}>
                <View style={{ flex: 1, gap: 6 }}>
                  <Text style={styles.personName}>{p.name}</Text>
                  <Bar fraction={p.shareFraction} color={p.isYou ? colors.accentStrong : colors.accent} />
                </View>
                <View style={{ alignItems: "flex-end" }}>
                  <Text style={styles.value}>{p.share}</Text>
                  <Text style={styles.small}>paid {p.paid}</Text>
                </View>
              </View>
            </View>
          ))}
        </Card>
      )}
      {page.categories.length > 0 && (
        <Card>
          <Text style={styles.eyebrow}>By category</Text>
          {page.categories.map((c, i) => (
            <View key={c.id}>
              {i > 0 && <Divider inset={16} />}
              <View style={styles.personRow}>
                <CategoryIcon icon={categoryIcon(c.categoryID)} categoryId={c.categoryID} size={24} />
                <View style={{ flex: 1, gap: 6 }}>
                  <Text style={styles.personName}>{c.name}</Text>
                  <Bar fraction={c.fraction} color={colors.accent} />
                </View>
                <View style={{ alignItems: "flex-end" }}>
                  <Text style={styles.value}>{c.amount}</Text>
                  <Text style={styles.small}>{Math.round(c.percent * 100)}%</Text>
                </View>
              </View>
            </View>
          ))}
        </Card>
      )}
    </View>
  );
}

function Summary({ page }: { page: Page }) {
  const share = page.people.find((p) => p.isYou)?.shareFraction ?? 0;
  const size = 116;
  const stroke = 14;
  const r = (size - stroke) / 2;
  const circumference = 2 * Math.PI * r;
  return (
    <Card>
      <View style={styles.summary}>
        <View
          style={{ width: size, height: size }}
          accessible
          accessibilityLabel={`Total spend ${page.totalSpent}${page.yourSharePercent ? `, your share is ${page.yourSharePercent}` : ""}`}
        >
          <Svg width={size} height={size}>
            <Circle cx={size / 2} cy={size / 2} r={r} stroke={colors.accentSoft} strokeWidth={stroke} fill="none" />
            <Circle
              cx={size / 2}
              cy={size / 2}
              r={r}
              stroke={colors.accentStrong}
              strokeWidth={stroke}
              fill="none"
              strokeDasharray={`${circumference * share} ${circumference}`}
              strokeLinecap="butt"
              transform={`rotate(-90 ${size / 2} ${size / 2})`}
            />
          </Svg>
          <View style={styles.donutCenter}>
            <Text style={styles.donutLabel}>TOTAL</Text>
            <Text style={styles.donutValue} adjustsFontSizeToFit numberOfLines={1}>
              {page.totalSpent}
            </Text>
          </View>
        </View>
        <View style={{ flex: 1, gap: 14 }}>
          <Stat label="You paid" value={page.youPaid} color={colors.text} />
          <Stat label="Your share" value={page.yourShare} color={colors.accentStrong} hint={page.yourSharePercent} />
        </View>
      </View>
    </Card>
  );
}

function Stat({ label, value, color, hint }: { label: string; value: string; color: string; hint?: string | null }) {
  return (
    <View>
      <Text style={styles.statLabel}>{label.toUpperCase()}</Text>
      <Text style={[styles.statValue, { color }]} adjustsFontSizeToFit numberOfLines={1}>
        {value}
      </Text>
      {hint && <Text style={styles.small}>{hint}</Text>}
    </View>
  );
}

function Bar({ fraction, color }: { fraction: number; color: string }) {
  return (
    <View style={styles.barTrack}>
      <View style={[styles.barFill, { width: `${Math.max(2, Math.min(100, fraction * 100))}%`, backgroundColor: color }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  empty: { alignItems: "center", paddingTop: 32, gap: 6, paddingHorizontal: 24 },
  emptyTitle: { fontSize: 15, fontWeight: "600", color: colors.text },
  muted: { fontSize: 13, color: colors.textSecondary, textAlign: "center" },
  currencies: { flexDirection: "row", gap: 8, paddingHorizontal: PAGE, paddingBottom: 10, flexWrap: "wrap" },
  summary: { flexDirection: "row", alignItems: "center", gap: 20, padding: 18 },
  donutCenter: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0, alignItems: "center", justifyContent: "center", paddingHorizontal: 22 },
  donutLabel: { fontSize: 8.5, fontWeight: "600", letterSpacing: 0.8, color: colors.textSecondary },
  donutValue: { fontSize: 13, fontWeight: "600", color: colors.text, fontVariant: ["tabular-nums"] },
  statLabel: { fontSize: 9.5, fontWeight: "600", letterSpacing: 0.6, color: colors.textSecondary },
  statValue: { fontSize: 19, fontWeight: "600", fontVariant: ["tabular-nums"], marginTop: 3 },
  eyebrow: { fontSize: 10, fontWeight: "600", letterSpacing: 1, color: colors.textSecondary, textTransform: "uppercase", paddingHorizontal: 16, paddingTop: 14, paddingBottom: 4 },
  personRow: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 12 },
  personName: { fontSize: 14, fontWeight: "500", color: colors.text },
  value: { fontSize: 13.5, fontWeight: "600", color: colors.text, fontVariant: ["tabular-nums"] },
  small: { fontSize: 11, color: colors.textSecondary, fontVariant: ["tabular-nums"], marginTop: 2 },
  barTrack: { height: 6, borderRadius: 3, backgroundColor: colors.surface2, overflow: "hidden" },
  barFill: { height: 6, borderRadius: 3 },
});
