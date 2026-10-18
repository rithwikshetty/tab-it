import { Image } from "expo-image";
import { router, Stack, useLocalSearchParams } from "expo-router";
import { useEffect, useMemo, useState } from "react";
import { ActivityIndicator, Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { deleteExpense } from "@/data/actions";
import { receiptSource } from "@/data/receipts";
import { isDirty } from "@/data/schema";
import { useAppState, useSignedIn } from "@/data/session";
import { formatMoney, paymentMethodDisplayName } from "@/domain";
import { dateTime, longDay, monthShort } from "@/lib/dates";
import { Avatar } from "@/ui/avatar";
import { CategoryIcon, categoryTone } from "@/ui/category-icon";
import { haptics } from "@/ui/haptics";
import { MoreMenu } from "@/ui/menu";
import { Banner, Button, Card, Divider, EmptyState, Icon, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE, type } from "@/ui/theme";

const SPLIT_LABEL: Record<string, string> = {
  equal: "equal",
  exact: "exact",
  percentage: "percentage",
  shares: "shares",
  adjustment: "adjustment",
};

export default function ExpenseDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const t = state.tables;
  const expense = t.expenses.get(id);

  const view = useMemo(() => {
    if (!expense) return null;
    const people = [...t.trip_people.values()].filter((p) => p.trip_id === expense.trip_id);
    const me = people.find((p) => p.user_id === ctx.user.id);
    const nameOf = (pid: string) => (pid === me?.id ? "You" : (people.find((p) => p.id === pid)?.display_name ?? "Member"));
    const order = (a: { id: string; name: string }, b: { id: string; name: string }) =>
      a.id === me?.id ? -1 : b.id === me?.id ? 1 : a.name.toLowerCase().localeCompare(b.name.toLowerCase());
    const payments = [...t.expense_payments.values()]
      .filter((p) => p.expense_id === id)
      .map((p) => ({ id: p.trip_person_id, name: nameOf(p.trip_person_id), amount: p.amount_paid }))
      .sort(order);
    const splitRows = [...t.expense_splits.values()].filter((s) => s.expense_id === id);
    const splits = splitRows.map((s) => ({ id: s.trip_person_id, name: nameOf(s.trip_person_id), amount: s.amount_owed })).sort(order);
    const category = t.categories.get(expense.category_id ?? "");
    const profileName = (uid: string | null) =>
      uid === ctx.user.id
        ? "You"
        : (people.find((p) => p.user_id === uid)?.display_name ?? t.profiles.get(uid ?? "")?.display_name ?? "Member");
    return {
      me,
      people,
      payments,
      splits,
      splitType: splitRows[0]?.split_type ?? "equal",
      category,
      loggedBy: profileName(expense.created_by),
      editedBy: expense.last_edited_by ? profileName(expense.last_edited_by) : null,
    };
  }, [expense, t, id, ctx.user.id]);

  if (!expense || expense.deleted_at || !view) {
    return (
      <>
        <Stack.Screen options={{ title: "", headerRight: () => null }} />
        <EmptyState
          icon="help-circle-outline"
          title="Expense not found"
          message="It may have been deleted."
          action={<Button title="Back" variant="secondary" onPress={() => router.back()} />}
        />
      </>
    );
  }

  const isCreator = expense.created_by === ctx.user.id;
  const money = (amount: string) => formatMoney(amount, expense.currency);

  function confirmDelete() {
    Alert.alert("Delete this expense?", "It will be removed from balances for everyone.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: async () => {
          await deleteExpense(ctx, id);
          haptics.success();
          router.back();
        },
      },
    ]);
  }

  return (
    <ScrollView style={styles.fill} contentContainerStyle={{ paddingBottom: 48 }}>
      <Stack.Screen
        options={{
          title: "",
          headerRight: () => (
            <MoreMenu
              label="Expense actions"
              items={[
                {
                  id: "edit",
                  title: "Edit expense",
                  symbol: "pencil",
                  onPress: () => router.push({ pathname: "/expense-form", params: { tripId: expense.trip_id, expenseId: id } }),
                },
                { id: "delete", title: "Delete expense", symbol: "trash", destructive: true, onPress: confirmDelete },
              ]}
            />
          ),
        }}
      />
      <View style={styles.header}>
        <View style={styles.categoryRow}>
          <CategoryIcon icon={view.category?.icon} categoryId={expense.category_id} size={18} />
          <Text style={[styles.categoryLabel, { color: categoryTone(expense.category_id) }]}>{view.category?.name ?? "Other"}</Text>
        </View>
        <Text style={[type.largeTitle, { marginTop: 4 }]}>{expense.description}</Text>
      </View>

      {expense._error ? (
        <Banner tone="warning" text={expense._error} action={{ label: "Review", onPress: () => router.push("/sync-issues") }} />
      ) : isDirty(expense) ? (
        <Banner text="Saved on this phone. It will sync when you're online." />
      ) : null}

      <View style={styles.totalCard}>
        <View style={{ flex: 1 }}>
          <Text style={styles.totalLabel}>TOTAL</Text>
          <Text style={styles.totalAmount} adjustsFontSizeToFit numberOfLines={1}>
            {money(expense.amount)}
          </Text>
        </View>
        <View style={{ alignItems: "flex-end" }}>
          <Text style={styles.day}>{Number(expense.expense_date.slice(8, 10))}</Text>
          <Text style={styles.month}>{monthShort(expense.expense_date)}</Text>
        </View>
      </View>

      <SectionHeader title="Paid by" />
      <Card>
        {view.payments.length === 1 && view.payments[0]!.id === view.me?.id ? (
          <Row title="You paid the bill" />
        ) : (
          view.payments.map((p, i) => (
            <View key={p.id}>
              {i > 0 && <Divider inset={58} />}
              <PersonAmount
                person={view.people.find((x) => x.id === p.id)}
                name={p.name}
                amount={money(p.amount)}
                me={view.me?.id}
                you={ctx.user.displayName}
              />
            </View>
          ))
        )}
      </Card>

      <SectionHeader title="Split" />
      <Card>
        {view.splits.map((s, i) => (
          <View key={s.id}>
            {i > 0 && <Divider inset={58} />}
            <PersonAmount
              person={view.people.find((x) => x.id === s.id)}
              name={s.name}
              amount={money(s.amount)}
              me={view.me?.id}
              you={ctx.user.displayName}
            />
          </View>
        ))}
        <Divider />
        <Text style={styles.splitFooter}>
          {SPLIT_LABEL[view.splitType] ?? view.splitType} · {view.splits.length} {view.splits.length === 1 ? "way" : "ways"}
        </Text>
      </Card>

      <SectionHeader title="Details" />
      <Card>
        <Row title="Date" value={longDay(expense.expense_date)} />
        <Divider inset={16} />
        <Row title="Paid via" value={paymentMethodDisplayName(expense.payment_method)} />
        <Divider inset={16} />
        <Row title="Logged by" value={view.loggedBy} />
        <Divider inset={16} />
        <Row title="Logged at" value={dateTime(expense.created_at)} />
        {view.editedBy && (
          <>
            <Divider inset={16} />
            <Row title="Edited by" value={view.editedBy} />
            <Divider inset={16} />
            <Row title="Edited at" value={dateTime(expense.updated_at)} />
          </>
        )}
      </Card>

      {expense.receipt_storage_path && (
        <>
          <SectionHeader title="Receipt" />
          <Receipt
            path={expense.receipt_storage_path}
            file={expense._receiptFile}
            version={expense.write_id}
            status={expense._receipt ?? null}
            isCreator={isCreator}
          />
        </>
      )}
    </ScrollView>
  );
}

function PersonAmount({
  person,
  name,
  amount,
  me,
  you,
}: {
  person?: { id: string; display_name: string; email: string; user_id: string | null };
  name: string;
  amount: string;
  me?: string;
  you: string;
}) {
  const isMe = person?.id === me;
  return (
    <View style={styles.personRow}>
      <Avatar
        person={{ id: person?.id ?? name, name: isMe ? you : name, userId: person?.user_id, email: person?.email }}
        size={30}
        ring={0}
      />
      <Text style={[styles.personName, isMe && { fontWeight: "600" }]} numberOfLines={1}>
        {name}
      </Text>
      <Text style={[styles.personAmount, isMe && { color: colors.text, fontWeight: "600" }]}>{amount}</Text>
    </View>
  );
}

function Receipt({
  path,
  file,
  version,
  status,
  isCreator,
}: {
  path: string;
  file?: string | null;
  version: string;
  status: "pending" | "failed" | null;
  isCreator: boolean;
}) {
  const { user } = useSignedIn();
  const [source, setSource] = useState<{ uri: string; cacheKey: string } | null>(null);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    let live = true;
    setError(false);
    receiptSource(user.id, path, file, version).then(
      (s) => live && setSource(s),
      () => live && setError(true),
    );
    return () => {
      live = false;
    };
  }, [user.id, path, file, version, attempt]);
  return (
    <Card>
      {status === "failed" && (
        <Text style={styles.receiptNote}>
          {isCreator
            ? "The photo couldn't be uploaded. Edit the expense and attach it again."
            : "Only the person who added this expense can upload its receipt."}
        </Text>
      )}
      {status === "pending" && <Text style={styles.receiptNote}>Uploading when you're online.</Text>}
      {error ? (
        <Pressable onPress={() => setAttempt((a) => a + 1)} style={styles.receiptBox} accessibilityRole="button">
          <Icon name="refresh" size={20} color={colors.textSecondary} />
          <Text style={type.small}>Couldn't load the receipt. Tap to try again.</Text>
        </Pressable>
      ) : !source ? (
        <View style={styles.receiptBox}>
          <ActivityIndicator color={colors.accent} />
        </View>
      ) : (
        <Pressable onPress={() => setOpen(true)} accessibilityRole="imagebutton" accessibilityLabel="Receipt photo. Open full screen">
          <Image
            source={{ uri: source.uri, cacheKey: source.cacheKey }}
            cachePolicy="disk"
            style={styles.receipt}
            contentFit="cover"
            onError={() => setError(true)}
          />
        </Pressable>
      )}
      <Modal visible={open} animationType="fade" onRequestClose={() => setOpen(false)}>
        <SafeAreaView style={styles.preview}>
          <Pressable onPress={() => setOpen(false)} style={styles.close} accessibilityRole="button" accessibilityLabel="Close">
            <Icon name="close" size={26} color="#fff" />
          </Pressable>
          {source && (
            <Image source={{ uri: source.uri, cacheKey: source.cacheKey }} cachePolicy="disk" style={{ flex: 1 }} contentFit="contain" />
          )}
        </SafeAreaView>
      </Modal>
    </Card>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  header: { paddingHorizontal: PAGE + 4, paddingTop: 4, paddingBottom: 14 },
  categoryRow: { flexDirection: "row", alignItems: "center", gap: 6 },
  categoryLabel: { fontSize: 12, fontWeight: "600", letterSpacing: 1.2, textTransform: "uppercase" },
  totalCard: {
    flexDirection: "row",
    alignItems: "flex-start",
    marginHorizontal: PAGE,
    padding: 18,
    paddingBottom: 26,
    borderRadius: 16,
    backgroundColor: colors.accentTint,
    borderWidth: 1,
    borderColor: colors.accentSoft,
  },
  totalLabel: { fontSize: 11, fontWeight: "600", letterSpacing: 1.1, color: colors.owed },
  totalAmount: { fontSize: 36, fontWeight: "700", color: colors.owed, letterSpacing: -0.8, marginTop: 4, fontVariant: ["tabular-nums"] },
  day: { fontSize: 26, fontWeight: "600", color: colors.textSecondary, fontFamily: "Georgia" },
  month: { fontSize: 12, letterSpacing: 1, color: colors.textSecondary },
  personRow: { flexDirection: "row", alignItems: "center", gap: 14, paddingHorizontal: 16, paddingVertical: 12 },
  personName: { flex: 1, fontSize: 15, color: colors.text },
  personAmount: { fontSize: 15, color: colors.textSecondary, fontVariant: ["tabular-nums"] },
  splitFooter: { fontSize: 12.5, color: colors.textSecondary, textAlign: "right", paddingHorizontal: 16, paddingVertical: 10 },
  receiptNote: { fontSize: 12.5, color: colors.warning, paddingHorizontal: 16, paddingTop: 12 },
  receiptBox: { height: 160, alignItems: "center", justifyContent: "center", gap: 8 },
  receipt: { height: 240, width: "100%" },
  preview: { flex: 1, backgroundColor: "#000" },
  close: { position: "absolute", top: 54, right: 18, zIndex: 2, padding: 8 },
});
