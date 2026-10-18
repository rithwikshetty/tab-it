import * as ImagePicker from "expo-image-picker";
import { Image } from "expo-image";
import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";

import { saveExpense, type ExpenseInput } from "@/data/actions";
import { localReceiptUri } from "@/data/receipts";
import { tripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import {
  computedDraftPayments,
  computedDraftSplits,
  convertAmountText,
  createPaymentSplitDraft,
  decimalFromInput,
  defaultCategories,
  enteredDraftTotal,
  formatMoney,
  fromMinor,
  hasValidPrecision,
  normalizeDecimal,
  plainAmountString,
  seedPaymentSplitDraft,
  selectedSplitType,
  setDraftText,
  setPayerMode,
  setSplitMode,
  sortedPeople,
  subtractDecimals,
  toMinor,
  togglePayer,
  toggleParticipant,
  type PaymentSplitDraft,
} from "@/domain";
import type { PaymentMethod, SplitType } from "@/domain/records";
import { CurrencyPicker, CurrencyPill } from "@/features/currency/currency-picker";
import { currencyFor, rememberCurrency } from "@/features/currency/defaults";
import { AmountInput } from "@/features/forms/amount-input";
import { DateField } from "@/features/forms/date-field";
import { todayDay } from "@/lib/dates";
import { Avatar } from "@/ui/avatar";
import { CategoryIcon } from "@/ui/category-icon";
import { haptics } from "@/ui/haptics";
import { Card, Divider, HeaderButton, Icon, Row, SectionHeader, Segmented } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

const SPLIT_MODES = [
  { value: "0", label: "Equal" },
  { value: "1", label: "Exact" },
  { value: "2", label: "Shares" },
  { value: "3", label: "Percent" },
];
const MODE_OF: Record<SplitType, number> = { equal: 0, exact: 1, adjustment: 1, shares: 2, percentage: 3 };
const METHODS: { value: PaymentMethod; label: string }[] = [
  { value: "cash", label: "Cash" },
  { value: "card", label: "Card" },
  { value: "bank_transfer", label: "Bank transfer" },
];

type ReceiptDraft = { action: "keep" } | { action: "remove" } | { action: "set"; uri: string; width: number; height: number };

export default function ExpenseForm() {
  const { tripId, expenseId } = useLocalSearchParams<{ tripId: string; expenseId?: string }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const rows = useMemo(() => tripRows(state, tripId), [state, tripId]);
  const editing = expenseId ? state.tables.expenses.get(expenseId) : undefined;
  const me = rows?.people.find((p) => p.user_id === ctx.user.id) ?? null;

  // People who can be picked: everyone active, plus removed people already on this expense.
  const members = useMemo(() => {
    if (!rows) return [];
    const onExpense = new Set([...rows.payments, ...rows.splits].filter((r) => r.expense_id === expenseId).map((r) => r.trip_person_id));
    return sortedPeople(
      rows.people.filter((p) => !p.removed_at || onExpense.has(p.id)),
      me?.id ?? null,
    );
  }, [rows, expenseId, me]);

  const seed = useMemo(() => {
    const currency = editing?.currency ?? currencyFor(state, tripId);
    const payments = rows?.payments.filter((p) => p.expense_id === expenseId) ?? [];
    const splits = rows?.splits.filter((s) => s.expense_id === expenseId) ?? [];
    const draft = seedPaymentSplitDraft(createPaymentSplitDraft(), {
      payments: payments.map((p) => ({
        payerID: p.trip_person_id,
        amountPaid: toMinor(p.amount_paid, currency),
        paymentMode: p.payment_mode,
      })),
      splitMode: splits[0] ? MODE_OF[splits[0].split_type] : 0,
      participantSet: splits.length ? splits.map((s) => s.trip_person_id) : members.filter((m) => !m.removed_at).map((m) => m.id),
      exactSplitAmountText: Object.fromEntries(splits.map((s) => [s.trip_person_id, plainAmountString(s.amount_owed, currency)])),
      shareSplitText: Object.fromEntries(splits.filter((s) => s.share_units).map((s) => [s.trip_person_id, s.share_units!])),
      percentSplitText: Object.fromEntries(splits.filter((s) => s.percentage).map((s) => [s.trip_person_id, s.percentage!])),
      currency,
      currentPersonID: me?.id ?? null,
      members: members.map((m) => m.id),
    });
    return {
      currency,
      amount: editing ? plainAmountString(editing.amount, currency) : "",
      draft,
    };
    // Seed once per screen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [currency, setCurrency] = useState(seed.currency);
  const [amountText, setAmountText] = useState(seed.amount);
  const [description, setDescription] = useState(editing?.description ?? "");
  const [categoryId, setCategoryId] = useState<string | null>(editing ? editing.category_id : (defaultCategories[0]?.id ?? null));
  const [day, setDay] = useState(editing?.expense_date ?? todayDay());
  const [method, setMethod] = useState<PaymentMethod>(editing?.payment_method ?? "card");
  const [draft, setDraft] = useState<PaymentSplitDraft>(seed.draft);
  const [receipt, setReceipt] = useState<ReceiptDraft>({ action: "keep" });
  const [pickingCurrency, setPickingCurrency] = useState(false);
  const [saving, setSaving] = useState(false);
  const [showErrors, setShowErrors] = useState(false);

  const total = decimalFromInput(amountText);
  const totalOk = total !== null && normalizeDecimal(total) !== "0" && !total.startsWith("-") && hasValidPrecision(total, currency);
  const totalString = totalOk ? normalizeDecimal(total!) : "0";
  const payments = totalOk ? computedDraftPayments(draft, totalString, currency) : null;
  const splits = totalOk ? computedDraftSplits(draft, totalString, currency) : null;
  const splitType = selectedSplitType(draft);
  const categories = useMemo(() => {
    const custom = (rows?.categories ?? []).filter((c) => !c.is_default);
    return [...defaultCategories, ...custom.map((c) => ({ id: c.id, name: c.name, icon: c.icon }))];
  }, [rows]);

  const isCreator = !editing || editing.created_by === ctx.user.id;
  const existingPath = editing?.receipt_storage_path ?? null;
  const receiptPreview =
    receipt.action === "set"
      ? receipt.uri
      : receipt.action === "keep" && existingPath
        ? localReceiptUri(existingPath, editing?._receiptFile)
        : null;
  const hasReceipt = receipt.action === "set" || (receipt.action === "keep" && !!existingPath);

  const problems = {
    amount: !totalOk ? (amountText ? "Enter a valid amount." : "Enter the amount.") : null,
    description: !description.trim() ? "Add a description." : null,
    payers: totalOk && !payments ? payerProblem(draft, totalString, currency) : null,
    split: totalOk && !splits ? splitProblem(draft, totalString, currency) : null,
  };
  const firstProblem = Object.values(problems).find(Boolean) ?? null;
  const canSave = !saving && !firstProblem && !!me;

  const nameOf = (id: string) => (id === me?.id ? "You" : (members.find((m) => m.id === id)?.display_name ?? "Member"));

  async function save() {
    if (!canSave || !payments || !splits) {
      setShowErrors(true);
      haptics.warning();
      if (firstProblem) Alert.alert("Can't save yet", firstProblem);
      return;
    }
    setSaving(true);
    try {
      const input: ExpenseInput = {
        id: editing?.id,
        tripId,
        amount: totalString,
        currency,
        categoryId,
        description,
        expenseDate: day,
        paymentMethod: method,
        payments: payments.map((p) => ({ personId: p.payerID, amount: fromMinor(p.amountPaid, currency), mode: p.paymentMode })),
        splits: splits.map((s) => ({
          personId: s.participantID,
          amount: fromMinor(s.amountOwed, currency),
          type: s.splitType,
          shareUnits: s.shareUnits,
          percentage: s.percentage,
        })),
        receipt,
      };
      await saveExpense(ctx, input);
      rememberCurrency(ctx, currency);
      haptics.success();
      router.back();
    } catch (e) {
      setSaving(false);
      Alert.alert("Couldn't save the expense", (e as Error).message);
    }
  }

  async function pickReceipt(source: "library" | "camera") {
    const options: ImagePicker.ImagePickerOptions = { mediaTypes: ["images"], quality: 1, allowsEditing: false };
    if (source === "camera") {
      const perm = await ImagePicker.requestCameraPermissionsAsync();
      if (!perm.granted) {
        Alert.alert("Camera access is off", "Allow camera access in Settings to photograph receipts.");
        return;
      }
    }
    const result = source === "camera" ? await ImagePicker.launchCameraAsync(options) : await ImagePicker.launchImageLibraryAsync(options);
    const asset = result.canceled ? null : result.assets[0];
    if (asset) setReceipt({ action: "set", uri: asset.uri, width: asset.width, height: asset.height });
  }

  if (!rows || !me || (expenseId && (!editing || editing.deleted_at))) {
    return (
      <View style={styles.missing}>
        <Stack.Screen options={{ title: "", headerLeft: () => <HeaderButton title="Close" onPress={() => router.back()} /> }} />
        <Text style={styles.missingText}>This {expenseId ? "expense" : "trip"} isn't available any more.</Text>
      </View>
    );
  }

  const amountFor = (minor: bigint | undefined) => (minor === undefined ? "" : formatMoney(minor, currency));
  const payerFooter = (() => {
    if (!totalOk || draft.selectedPayerIDs.length < 2) return null;
    if (draft.payerMode !== "exact") {
      const each = payments?.[0]?.amountPaid;
      return {
        text:
          payments && payments.every((p) => p.amountPaid === each)
            ? `Each pays ${amountFor(each)}`
            : `Equal total ${formatMoney(totalString, currency)}`,
        warn: false,
      };
    }
    return reconcile(enteredDraftTotal(draft.selectedPayerIDs, draft.exactPayerAmountText), totalString, currency);
  })();

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen
        options={{
          title: editing ? "Edit expense" : "New expense",
          headerLeft: () => <HeaderButton title="Cancel" onPress={() => router.back()} />,
          headerRight: () => <HeaderButton title="Save" bold loading={saving} onPress={save} disabled={saving} />,
        }}
      />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 60 }}>
        <View style={styles.amountBlock}>
          <AmountInput
            value={amountText}
            currency={currency}
            autoFocus={!editing}
            onChange={(text) => {
              setAmountText(text);
            }}
          />
          <CurrencyPill code={currency} onPress={() => setPickingCurrency(true)} />
          {showErrors && problems.amount && <Text style={styles.error}>{problems.amount}</Text>}
        </View>

        <View style={styles.section}>
          <TextInput
            value={description}
            onChangeText={setDescription}
            placeholder="What was it for?"
            placeholderTextColor={colors.textTertiary}
            maxLength={200}
            style={[styles.description, showErrors && problems.description ? { borderColor: colors.danger } : null]}
            returnKeyType="done"
            accessibilityLabel="Description"
          />
          {showErrors && problems.description && <Text style={styles.error}>{problems.description}</Text>}
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.categories}>
          {categories.map((c) => {
            const selected = c.id === categoryId;
            return (
              <Pressable
                key={c.id}
                accessibilityRole="button"
                accessibilityState={{ selected }}
                accessibilityLabel={c.name}
                onPress={() => {
                  haptics.selection();
                  setCategoryId(c.id);
                }}
                style={[styles.category, selected && styles.categorySelected]}
              >
                <CategoryIcon icon={c.icon} categoryId={c.id} size={20} />
                <Text style={[styles.categoryText, selected && { color: colors.accentStrong, fontWeight: "600" }]}>{c.name}</Text>
              </Pressable>
            );
          })}
        </ScrollView>

        <SectionHeader
          title="Paid by"
          right={
            draft.selectedPayerIDs.length > 1 ? <Text style={styles.headerNote}>{draft.selectedPayerIDs.length} people</Text> : undefined
          }
        />
        <Card>
          <View style={styles.chips}>
            {members.map((m) => {
              const selected = draft.selectedPayerIDs.includes(m.id);
              return (
                <Pressable
                  key={m.id}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: selected }}
                  accessibilityLabel={`${nameOf(m.id)} paid`}
                  onPress={() => {
                    haptics.selection();
                    setDraft((d) => togglePayer(d, m.id, totalString, currency));
                  }}
                  style={[styles.personChip, selected && styles.personChipOn]}
                >
                  <Avatar
                    person={{ id: m.id, name: m.id === me.id ? ctx.user.displayName : m.display_name, userId: m.user_id, email: m.email }}
                    size={22}
                    ring={0}
                  />
                  <Text style={[styles.personChipText, selected && { color: colors.accentStrong }]} numberOfLines={1}>
                    {nameOf(m.id)}
                  </Text>
                </Pressable>
              );
            })}
          </View>
          {draft.selectedPayerIDs.length > 1 && (
            <>
              <Segmented
                style={{ marginHorizontal: 14, marginBottom: 6 }}
                value={draft.payerMode === "exact" ? "exact" : "equal"}
                onChange={(v) => setDraft((d) => setPayerMode(d, v as SplitType, totalString, currency))}
                options={[
                  { value: "equal", label: "Split equally" },
                  { value: "exact", label: "Exact amounts" },
                ]}
              />
              {draft.selectedPayerIDs.map((id) => (
                <View key={id}>
                  <Divider inset={16} />
                  <View style={styles.lineRow}>
                    <Text style={[styles.lineName, { flex: 1 }]} numberOfLines={1}>
                      {nameOf(id)}
                    </Text>
                    {draft.payerMode === "exact" ? (
                      <MoneyField
                        value={draft.exactPayerAmountText[id] ?? ""}
                        currency={currency}
                        onChange={(v) => setDraft((d) => setDraftText(d, "payer", id, v, currency))}
                      />
                    ) : (
                      <Pressable
                        onPress={() => setDraft((d) => setPayerMode(d, "exact", totalString, currency))}
                        accessibilityRole="button"
                        accessibilityLabel={`Change ${nameOf(id)}'s amount`}
                      >
                        <Text style={styles.computed}>{amountFor(payments?.find((p) => p.payerID === id)?.amountPaid)}</Text>
                      </Pressable>
                    )}
                  </View>
                </View>
              ))}
            </>
          )}
          {payerFooter && <Footer text={payerFooter.text} warn={payerFooter.warn} />}
        </Card>
        {showErrors && problems.payers && <Text style={styles.error}>{problems.payers}</Text>}

        <SectionHeader
          title="Split"
          right={
            <Text style={styles.headerNote}>
              {draft.selectedParticipants.length} of {members.length}
            </Text>
          }
        />
        <Card>
          <Segmented
            style={{ marginHorizontal: 14, marginVertical: 12 }}
            value={String(draft.splitMode)}
            onChange={(v) => setDraft((d) => setSplitMode(d, Number(v), totalString, currency))}
            options={SPLIT_MODES}
          />
          {members.map((m) => {
            const on = draft.selectedParticipants.includes(m.id);
            const owed = splits?.find((s) => s.participantID === m.id)?.amountOwed;
            return (
              <View key={m.id}>
                <Divider inset={16} />
                <View style={styles.lineRow}>
                  <Pressable
                    accessibilityRole="checkbox"
                    accessibilityState={{ checked: on }}
                    accessibilityLabel={`Include ${nameOf(m.id)}`}
                    onPress={() => {
                      haptics.selection();
                      setDraft((d) => toggleParticipant(d, m.id, totalString, currency));
                    }}
                    style={styles.check}
                    hitSlop={6}
                  >
                    <Icon name={on ? "checkmark-circle" : "ellipse-outline"} size={24} color={on ? colors.accent : colors.textTertiary} />
                    <Text style={[styles.lineName, !on && { color: colors.textTertiary }]} numberOfLines={1}>
                      {nameOf(m.id)}
                    </Text>
                  </Pressable>
                  {on && splitType === "equal" && (
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`Change ${nameOf(m.id)}'s share`}
                      onPress={() => setDraft((d) => setSplitMode(d, 1, totalString, currency, true))}
                    >
                      <Text style={styles.computed}>{amountFor(owed)}</Text>
                    </Pressable>
                  )}
                  {on && splitType === "exact" && (
                    <MoneyField
                      value={draft.exactSplitAmountText[m.id] ?? ""}
                      currency={currency}
                      onChange={(v) => setDraft((d) => setDraftText(d, "exact", m.id, v, currency))}
                    />
                  )}
                  {on && (splitType === "shares" || splitType === "percentage") && (
                    <View style={styles.weight}>
                      <Text style={styles.computedSmall}>{amountFor(owed)}</Text>
                      <TextInput
                        value={(splitType === "shares" ? draft.shareSplitText : draft.percentSplitText)[m.id] ?? ""}
                        onChangeText={(v) =>
                          setDraft((d) => setDraftText(d, splitType === "shares" ? "shares" : "percentage", m.id, v, currency))
                        }
                        keyboardType="decimal-pad"
                        style={styles.weightInput}
                        selectTextOnFocus
                        accessibilityLabel={`${nameOf(m.id)} ${splitType === "shares" ? "shares" : "percent"}`}
                      />
                      <Text style={styles.unit}>{splitType === "shares" ? "×" : "%"}</Text>
                    </View>
                  )}
                </View>
              </View>
            );
          })}
          {splitFooter(draft, totalString, currency, totalOk) && <Footer {...splitFooter(draft, totalString, currency, totalOk)!} />}
        </Card>
        {showErrors && problems.split && <Text style={styles.error}>{problems.split}</Text>}

        <SectionHeader title="Details" />
        <Card>
          <DateField label="Date" day={day} onChange={setDay} />
          <Divider inset={16} />
          <View style={{ padding: 12 }}>
            <Text style={styles.fieldLabel}>Paid via</Text>
            <Segmented
              style={{ marginHorizontal: 0, marginTop: 8 }}
              value={method}
              onChange={(v) => setMethod(v as PaymentMethod)}
              options={METHODS}
            />
          </View>
        </Card>

        <SectionHeader title="Receipt" />
        <Card>
          {!isCreator ? (
            <Row
              title={hasReceipt ? "Receipt attached" : "No receipt"}
              subtitle="Only the person who added this expense can change its receipt."
            />
          ) : hasReceipt ? (
            <View style={styles.receiptRow}>
              {receiptPreview ? (
                <Image source={{ uri: receiptPreview }} style={styles.thumb} contentFit="cover" />
              ) : (
                <View style={[styles.thumb, styles.thumbEmpty]}>
                  <Icon name="receipt-outline" size={22} color={colors.textSecondary} />
                </View>
              )}
              <Text style={[styles.lineName, { flex: 1 }]}>{receipt.action === "set" ? "New photo" : "Receipt attached"}</Text>
              <Pressable onPress={() => pickReceipt("library")} hitSlop={8} accessibilityRole="button">
                <Text style={styles.link}>Replace</Text>
              </Pressable>
              <Pressable
                onPress={() => setReceipt(existingPath ? { action: "remove" } : { action: "keep" })}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="Remove receipt"
              >
                <Icon name="close-circle" size={22} color={colors.textTertiary} />
              </Pressable>
            </View>
          ) : (
            <View style={styles.receiptButtons}>
              <Pressable onPress={() => pickReceipt("camera")} style={styles.receiptButton} accessibilityRole="button">
                <Icon name="camera-outline" size={20} color={colors.accentStrong} />
                <Text style={styles.link}>Take photo</Text>
              </Pressable>
              <View style={styles.vDivider} />
              <Pressable onPress={() => pickReceipt("library")} style={styles.receiptButton} accessibilityRole="button">
                <Icon name="image-outline" size={20} color={colors.accentStrong} />
                <Text style={styles.link}>Choose photo</Text>
              </Pressable>
            </View>
          )}
        </Card>
      </ScrollView>
      <CurrencyPicker
        visible={pickingCurrency}
        value={currency}
        onPick={(code) => {
          setAmountText((a) => convertAmountText(a, code));
          setDraft((d) => ({
            ...d,
            exactPayerAmountText: Object.fromEntries(
              Object.entries(d.exactPayerAmountText).map(([k, v]) => [k, convertAmountText(v, code)]),
            ),
            exactSplitAmountText: Object.fromEntries(
              Object.entries(d.exactSplitAmountText).map(([k, v]) => [k, convertAmountText(v, code)]),
            ),
          }));
          setCurrency(code);
          rememberCurrency(ctx, code);
        }}
        onClose={() => setPickingCurrency(false)}
      />
    </KeyboardAvoidingView>
  );
}

function MoneyField({ value, currency, onChange }: { value: string; currency: string; onChange: (v: string) => void }) {
  return (
    <TextInput
      value={value}
      onChangeText={onChange}
      keyboardType="decimal-pad"
      placeholder={plainAmountString(0n, currency)}
      placeholderTextColor={colors.textTertiary}
      style={styles.moneyField}
      selectTextOnFocus
    />
  );
}

function Footer({ text, warn }: { text: string; warn: boolean }) {
  return (
    <>
      <Divider />
      <Text style={[styles.footer, warn && { color: colors.warning, fontWeight: "600" }]}>{text}</Text>
    </>
  );
}

/** "Remaining £3.00" / "Over by £1.00" / "Exact total £20.00" for typed amounts. */
function reconcile(entered: string, total: string, currency: string): { text: string; warn: boolean } {
  const diff = subtractDecimals(total, entered);
  const minor = toMinor(diff, currency);
  if (minor === 0n) return { text: `Exact total ${formatMoney(total, currency)}`, warn: false };
  return minor > 0n
    ? { text: `Remaining ${formatMoney(minor, currency)}`, warn: true }
    : { text: `Over by ${formatMoney(-minor, currency)}`, warn: true };
}

function splitFooter(draft: PaymentSplitDraft, total: string, currency: string, totalOk: boolean): { text: string; warn: boolean } | null {
  const type = selectedSplitType(draft);
  const ids = draft.selectedParticipants;
  if (type === "equal" || !totalOk) return null;
  if (type === "exact") return reconcile(enteredDraftTotal(ids, draft.exactSplitAmountText), total, currency);
  if (type === "shares") {
    if (ids.some((id) => !(Number(draft.shareSplitText[id] ?? 0) > 0))) return { text: "Every participant needs a share", warn: true };
    return { text: `${normalizeDecimal(enteredDraftTotal(ids, draft.shareSplitText))} shares total`, warn: false };
  }
  const sum = normalizeDecimal(enteredDraftTotal(ids, draft.percentSplitText));
  const left = normalizeDecimal(subtractDecimals("100", sum));
  if (left === "0") return { text: "Total 100%", warn: false };
  return left.startsWith("-") ? { text: `Over by ${left.slice(1)}%`, warn: true } : { text: `${left}% left`, warn: true };
}

function payerProblem(draft: PaymentSplitDraft, total: string, currency: string): string {
  if (draft.payerMode === "exact") {
    const r = reconcile(enteredDraftTotal(draft.selectedPayerIDs, draft.exactPayerAmountText), total, currency);
    if (r.warn) return `What people paid must add up to the total. ${r.text}.`;
  }
  return "Check who paid.";
}

function splitProblem(draft: PaymentSplitDraft, total: string, currency: string): string {
  const footer = splitFooter(draft, total, currency, true);
  if (footer?.warn) return `The split doesn't add up. ${footer.text}.`;
  return "Check the split amounts.";
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  missing: { flex: 1, alignItems: "center", justifyContent: "center", padding: 32, backgroundColor: colors.bg },
  missingText: { fontSize: 15, color: colors.textSecondary, textAlign: "center" },
  amountBlock: { alignItems: "center", paddingTop: 18, paddingBottom: 6, gap: 8 },
  section: { paddingHorizontal: PAGE, paddingTop: 12 },
  description: {
    minHeight: 50,
    borderRadius: radius.control,
    borderWidth: 1,
    borderColor: colors.cardBorder,
    backgroundColor: colors.surface,
    paddingHorizontal: 14,
    fontSize: 17,
    color: colors.text,
  },
  categories: { gap: 8, paddingHorizontal: PAGE, paddingTop: 12 },
  category: {
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
  categorySelected: { backgroundColor: colors.accentTint, borderColor: colors.accentSoft },
  categoryText: { fontSize: 13.5, color: colors.text, fontWeight: "500" },
  headerNote: { fontSize: 12, color: colors.textSecondary },
  chips: { flexDirection: "row", flexWrap: "wrap", gap: 8, padding: 12 },
  personChip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingLeft: 4,
    paddingRight: 12,
    paddingVertical: 4,
    borderRadius: radius.pill,
    backgroundColor: colors.surface2,
    borderWidth: 1,
    borderColor: "transparent",
    maxWidth: 170,
  },
  personChipOn: { backgroundColor: colors.accentTint, borderColor: colors.accentSoft },
  personChipText: { fontSize: 14, fontWeight: "500", color: colors.text, flexShrink: 1 },
  lineRow: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, minHeight: 50 },
  lineName: { fontSize: 15, color: colors.text, flexShrink: 1 },
  check: { flexDirection: "row", alignItems: "center", gap: 10, flex: 1, paddingVertical: 10 },
  computed: { fontSize: 15, fontWeight: "500", color: colors.textSecondary, fontVariant: ["tabular-nums"], paddingVertical: 10 },
  computedSmall: { fontSize: 13, color: colors.textSecondary, fontVariant: ["tabular-nums"] },
  moneyField: {
    minWidth: 96,
    textAlign: "right",
    fontSize: 15,
    color: colors.text,
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 8,
    backgroundColor: colors.surface2,
    fontVariant: ["tabular-nums"],
  },
  weight: { flexDirection: "row", alignItems: "center", gap: 8 },
  weightInput: {
    minWidth: 54,
    textAlign: "right",
    fontSize: 15,
    color: colors.text,
    paddingHorizontal: 8,
    paddingVertical: 7,
    borderRadius: 8,
    backgroundColor: colors.surface2,
  },
  unit: { fontSize: 14, color: colors.textSecondary, width: 14 },
  footer: { fontSize: 12.5, color: colors.textSecondary, textAlign: "right", paddingHorizontal: 16, paddingVertical: 10 },
  error: { fontSize: 13, color: colors.danger, marginTop: 6, paddingHorizontal: PAGE + 4 },
  fieldLabel: { fontSize: 15, fontWeight: "500", color: colors.text, paddingHorizontal: 4 },
  receiptRow: { flexDirection: "row", alignItems: "center", gap: 12, padding: 12 },
  thumb: { width: 48, height: 48, borderRadius: 8, backgroundColor: colors.surface2 },
  thumbEmpty: { alignItems: "center", justifyContent: "center" },
  receiptButtons: { flexDirection: "row" },
  receiptButton: { flex: 1, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 8, paddingVertical: 15 },
  vDivider: { width: StyleSheet.hairlineWidth * 2, backgroundColor: colors.rowDivider },
  link: { fontSize: 15, fontWeight: "500", color: colors.accentStrong },
});
