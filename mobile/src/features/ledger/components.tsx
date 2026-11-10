import { memo } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";

import type { BalanceSemantic, BalanceSummary, ExpenseRowItem, SettlementRowItem, SimplifiedDebtGroup, TimelineDay } from "@/domain";
import { CategoryIcon } from "@/ui/category-icon";
import { haptics } from "@/ui/haptics";
import { Card, Divider, Icon, sameValues } from "@/ui/primitives";
import { colors, PAGE, radius, type } from "@/ui/theme";

// The pieces every ledger view shares: expense and payment rows, the balance
// card, simplified debts and the day-grouped timeline.

export function toneFor(semantic: BalanceSemantic): string {
  return semantic === "lent" ? colors.owed : semantic === "borrowed" ? colors.owe : colors.text;
}

export function ExpenseRow({ item, onPress, pending }: { item: ExpenseRowItem; onPress: () => void; pending?: boolean }) {
  const caption =
    item.netAmount === null
      ? "your share"
      : item.balanceSemantic === "lent"
        ? "you lent"
        : item.balanceSemantic === "borrowed"
          ? "you borrowed"
          : "your share";
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${item.name}, ${item.totalAmount}, paid by ${item.payerName}, ${caption} ${item.netAmount ?? item.yourShare}`}
      onPress={() => {
        haptics.light();
        onPress();
      }}
      android_ripple={{ color: colors.rowDivider }}
      style={({ pressed }) => [styles.expenseRow, pressed && { backgroundColor: colors.surface2 }]}
    >
      <CategoryIcon icon={item.icon} categoryId={item.categoryID} size={30} />
      <View style={styles.flex}>
        <Text style={styles.expenseName} numberOfLines={1}>
          {item.name}
        </Text>
        <Text style={styles.meta} numberOfLines={1}>
          {[item.sourceName, `Paid by ${item.payerName}`, item.totalAmount].filter(Boolean).join(" · ")}
        </Text>
      </View>
      <View style={styles.amountCol}>
        <Text style={[styles.amount, { color: item.netAmount === null ? colors.text : toneFor(item.balanceSemantic) }]} numberOfLines={1}>
          {item.netAmount ?? item.yourShare}
        </Text>
        <Text style={styles.caption}>{pending ? "not synced yet" : caption}</Text>
      </View>
      <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
    </Pressable>
  );
}

export function SettlementRow({ item, onPress }: { item: SettlementRowItem; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${item.text}, ${item.formattedAmount}`}
      onPress={() => {
        haptics.light();
        onPress();
      }}
      style={({ pressed }) => [styles.settlementCard, pressed && { opacity: 0.7 }]}
    >
      <View style={styles.settleIcon}>
        <Icon name="arrow-forward" size={15} color={colors.settle} />
      </View>
      <View style={styles.flex}>
        <Text style={styles.settleText} numberOfLines={1}>
          {item.text}
        </Text>
        {item.sourceName && (
          <Text style={[styles.meta, { fontSize: 11 }]} numberOfLines={1}>
            {item.sourceName}
          </Text>
        )}
      </View>
      <Text style={[styles.amount, { color: colors.settle }]}>{item.formattedAmount}</Text>
      <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
    </Pressable>
  );
}

export function BalanceCard({ summary }: { summary: BalanceSummary }) {
  const tone = summary.semantic === "borrowed" ? colors.owe : colors.owed;
  const tint = summary.semantic === "borrowed" ? "#F7EEE7" : colors.accentTint;
  return (
    <View style={[styles.balanceCard, { backgroundColor: tint, borderColor: `${tone}40` }]}>
      <Text style={[styles.balanceLabel, { color: tone }]}>{summary.label}</Text>
      <Text style={[styles.balanceAmount, { color: tone }]} adjustsFontSizeToFit numberOfLines={1}>
        {summary.amount}
      </Text>
      {summary.details.length > 0 && (
        <View style={[styles.balanceDetails, { borderTopColor: `${tone}40` }]}>
          {summary.details.map((d) => (
            <View key={d.id} style={styles.balanceDetail}>
              <Text style={styles.balanceDetailText} numberOfLines={1}>
                {d.counterparty}
              </Text>
              <Text style={[styles.balanceDetailAmount, { color: toneFor(d.semantic) }]}>{d.amount}</Text>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

export function SettledCard({ title = "All settled", message = "Add an expense to start tracking" }: { title?: string; message?: string }) {
  return (
    <View style={[styles.balanceCard, styles.settled]}>
      <Text style={styles.settledTitle}>{title}</Text>
      <Text style={styles.meta}>{message}</Text>
    </View>
  );
}

export function DebtGroups({
  groups,
  onSettle,
}: {
  groups: SimplifiedDebtGroup[];
  onSettle: (debt: SimplifiedDebtGroup["debts"][number]) => void;
}) {
  return (
    <>
      {groups.map((group) => (
        <Card key={group.id}>
          {groups.length > 1 && <Text style={styles.currencyLabel}>{group.currency}</Text>}
          {group.debts.map((debt, i) => (
            <View key={debt.id}>
              {i > 0 && <Divider inset={16} />}
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={`${debt.fromName} ${debt.semantic === "borrowed" ? "owe" : "owes"} ${debt.toName} ${debt.amount}. Settle up`}
                onPress={() => {
                  haptics.light();
                  onSettle(debt);
                }}
                style={({ pressed }) => [styles.debtRow, pressed && { backgroundColor: colors.surface2 }]}
              >
                <Text style={[styles.flex, styles.debtText]} numberOfLines={1}>
                  <Text style={{ color: colors.owe }}>{debt.fromName}</Text>
                  <Text style={{ color: colors.textSecondary }}>{debt.semantic === "borrowed" ? " owe " : " owes "}</Text>
                  <Text style={{ color: colors.owed }}>{debt.toName}</Text>
                </Text>
                <View style={styles.amountCol}>
                  <Text style={[styles.debtAmount, { color: toneFor(debt.semantic) }]}>{debt.amount}</Text>
                  <Text style={styles.caption}>Settle up</Text>
                </View>
                <Icon name="chevron-forward" size={14} color={colors.textTertiary} />
              </Pressable>
            </View>
          ))}
        </Card>
      ))}
    </>
  );
}

/** One item of the virtualised timeline: a day heading, an expense row or a payment. */
export type TimelineEntry =
  | { kind: "day"; key: string; dateLabel: string; totals: TimelineDay["totals"] }
  | { kind: "expense"; key: string; item: ExpenseRowItem; first: boolean; last: boolean; pending: boolean }
  | { kind: "settlement"; key: string; item: SettlementRowItem };

/** Flattens day-grouped items into list entries; consecutive expenses on a day share a card. */
export function timelineEntries(days: TimelineDay[], pendingIds: ReadonlySet<string>): TimelineEntry[] {
  const entries: TimelineEntry[] = [];
  for (const day of days) {
    entries.push({ kind: "day", key: day.id, dateLabel: day.dateLabel, totals: day.totals });
    day.items.forEach((item, i) => {
      if (item.type === "settlement") entries.push({ kind: "settlement", key: item.id, item: item.settlement });
      else
        entries.push({
          kind: "expense",
          key: item.id,
          item: item.expense,
          first: day.items[i - 1]?.type !== "expense",
          last: day.items[i + 1]?.type !== "expense",
          pending: pendingIds.has(item.id),
        });
    });
  }
  return entries;
}

/** Renders one timeline entry; re-renders only when the values it shows change. */
export const TimelineRow = memo(function TimelineRow({
  entry,
  onOpenExpense,
  onOpenSettlement,
}: {
  entry: TimelineEntry;
  onOpenExpense: (id: string) => void;
  onOpenSettlement: (id: string) => void;
}) {
  if (entry.kind === "day")
    return (
      <View style={styles.dayHeader}>
        <Text style={styles.dayLabel}>{entry.dateLabel.toUpperCase()}</Text>
        <View style={{ alignItems: "flex-end", flexShrink: 1 }}>
          {entry.totals.map((t) => (
            <Text key={t.id} style={styles.dayTotal} numberOfLines={1}>
              {t.totalSpend} · your share {t.yourShare}
            </Text>
          ))}
        </View>
      </View>
    );
  if (entry.kind === "settlement") return <SettlementRow item={entry.item} onPress={() => onOpenSettlement(entry.item.id)} />;
  return (
    <Card first={entry.first} last={entry.last} style={{ marginBottom: 6 }}>
      {!entry.first && <Divider inset={58} />}
      <ExpenseRow item={entry.item} pending={entry.pending} onPress={() => onOpenExpense(entry.item.id)} />
    </Card>
  );
}, sameValues);

const styles = StyleSheet.create({
  flex: { flex: 1, minWidth: 0 },
  expenseRow: { flexDirection: "row", alignItems: "center", paddingHorizontal: 14, paddingVertical: 12, gap: 14 },
  expenseName: { fontSize: 15, fontWeight: "500", color: colors.text, letterSpacing: -0.1 },
  meta: { fontSize: 12, color: colors.textSecondary, marginTop: 2 },
  amountCol: { alignItems: "flex-end" },
  amount: { fontSize: 15, fontWeight: "600", fontVariant: ["tabular-nums"] },
  caption: { fontSize: 10, fontWeight: "500", color: colors.textSecondary, marginTop: 1 },
  settlementCard: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    marginHorizontal: PAGE,
    marginBottom: 6,
    paddingHorizontal: 14,
    paddingVertical: 11,
    backgroundColor: colors.surface,
    borderRadius: radius.card,
    borderWidth: 1,
    borderColor: "rgba(107,141,166,0.22)",
  },
  settleIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: "rgba(107,141,166,0.12)",
    alignItems: "center",
    justifyContent: "center",
  },
  settleText: { fontSize: 13, color: colors.textSecondary },
  balanceCard: { marginHorizontal: PAGE, marginBottom: 12, padding: 18, borderRadius: 16, borderWidth: 1, overflow: "hidden" },
  balanceLabel: { fontSize: 11, fontWeight: "600", letterSpacing: 1.1, textTransform: "uppercase", opacity: 0.9 },
  balanceAmount: { ...type.balanceAmount, marginTop: 4 },
  balanceDetails: { borderTopWidth: 1, marginTop: 10, paddingTop: 8, gap: 4 },
  balanceDetail: { flexDirection: "row", justifyContent: "space-between", gap: 12 },
  balanceDetailText: { flex: 1, fontSize: 13, color: "rgba(40,40,31,0.78)" },
  balanceDetailAmount: { fontSize: 13, fontWeight: "600", fontVariant: ["tabular-nums"] },
  settled: { backgroundColor: colors.accentTint, borderColor: colors.accentSoft, alignItems: "center", paddingVertical: 22, gap: 4 },
  settledTitle: { fontSize: 15, fontWeight: "600", color: colors.text },
  currencyLabel: { fontSize: 10, fontWeight: "600", letterSpacing: 1, color: colors.textSecondary, paddingHorizontal: 16, paddingTop: 14 },
  debtRow: { flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: 16, paddingVertical: 12 },
  debtText: { fontSize: 14 },
  debtAmount: { fontSize: 14, fontWeight: "600", fontVariant: ["tabular-nums"] },
  dayHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
    gap: 10,
    paddingHorizontal: PAGE + 8,
    paddingTop: 18,
    paddingBottom: 6,
  },
  dayLabel: { fontSize: 11, fontWeight: "600", letterSpacing: 1.3, color: colors.textSecondary },
  dayTotal: { fontSize: 10.5, fontWeight: "600", color: colors.textSecondary, fontVariant: ["tabular-nums"] },
});
