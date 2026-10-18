import { Pressable, StyleSheet, Text, View } from "react-native";

import type { BalanceSemantic, BalanceSummary, ExpenseRowItem, SettlementRowItem, SimplifiedDebtGroup, TimelineDay } from "@/domain";
import { CategoryIcon } from "@/ui/category-icon";
import { haptics } from "@/ui/haptics";
import { Card, Divider, Icon } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

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

/** Day-grouped expenses and payments; consecutive expenses share a card. */
export function Timeline({
  days,
  onOpenExpense,
  onOpenSettlement,
  pendingIds,
}: {
  days: TimelineDay[];
  onOpenExpense: (id: string) => void;
  onOpenSettlement: (id: string) => void;
  pendingIds?: ReadonlySet<string>;
}) {
  return (
    <>
      {days.map((day) => {
        const blocks: ({ kind: "expenses"; items: ExpenseRowItem[] } | { kind: "settlement"; item: SettlementRowItem })[] = [];
        for (const item of day.items) {
          const last = blocks[blocks.length - 1];
          if (item.type === "expense") {
            if (last?.kind === "expenses") last.items.push(item.expense);
            else blocks.push({ kind: "expenses", items: [item.expense] });
          } else blocks.push({ kind: "settlement", item: item.settlement });
        }
        return (
          <View key={day.id}>
            <View style={styles.dayHeader}>
              <Text style={styles.dayLabel}>{day.dateLabel.toUpperCase()}</Text>
              <View style={{ alignItems: "flex-end", flexShrink: 1 }}>
                {day.totals.map((t) => (
                  <Text key={t.id} style={styles.dayTotal} numberOfLines={1}>
                    {t.totalSpend} · your share {t.yourShare}
                  </Text>
                ))}
              </View>
            </View>
            {blocks.map((block, bi) =>
              block.kind === "expenses" ? (
                <Card key={`e${bi}`} style={{ marginBottom: 6 }}>
                  {block.items.map((e, i) => (
                    <View key={e.id}>
                      {i > 0 && <Divider inset={58} />}
                      <ExpenseRow item={e} pending={pendingIds?.has(e.id)} onPress={() => onOpenExpense(e.id)} />
                    </View>
                  ))}
                </Card>
              ) : (
                <SettlementRow key={block.item.id} item={block.item} onPress={() => onOpenSettlement(block.item.id)} />
              ),
            )}
          </View>
        );
      })}
    </>
  );
}

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
  balanceAmount: { fontSize: 34, fontWeight: "700", letterSpacing: -0.8, marginTop: 4, fontVariant: ["tabular-nums"] },
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
