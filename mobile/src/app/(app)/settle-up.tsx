import { router, Stack, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";

import { saveSettlement } from "@/data/actions";
import { tripRows } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import {
  balancesFromRows,
  formatMoney,
  fromMinor,
  plainAmountString,
  simplifyDebts,
  sortedPeople,
  suggestedPayment,
  toMinor,
  parseAmountInput,
  convertAmountText,
} from "@/domain";
import { CurrencyPicker, CurrencyPill } from "@/features/currency/currency-picker";
import { currencyFor, rememberCurrency } from "@/features/currency/defaults";
import { AmountInput } from "@/features/forms/amount-input";
import { DateField } from "@/features/forms/date-field";
import { PersonSelect, type SelectablePerson } from "@/features/forms/person-select";
import { dayOf, todayDay } from "@/lib/dates";
import { haptics } from "@/ui/haptics";
import { Card, Divider, HeaderButton, Icon, Row, SectionHeader } from "@/ui/primitives";
import { colors, PAGE, radius } from "@/ui/theme";

/** When the payment day is today, keep the actual time; otherwise noon that day. */
function settledAtFor(day: string, previous?: string): string {
  if (previous && dayOf(new Date(previous)) === day) return previous;
  if (day === todayDay()) return new Date().toISOString();
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y!, m! - 1, d!, 12).toISOString();
}

export default function SettleUp() {
  const params = useLocalSearchParams<{
    tripId: string;
    settlementId?: string;
    from?: string;
    to?: string;
    amount?: string;
    currency?: string;
  }>();
  const ctx = useSignedIn();
  const state = useAppState();
  const tripId = params.tripId;
  const editing = params.settlementId ? state.tables.settlements.get(params.settlementId) : undefined;

  const rows = useMemo(() => tripRows(state, tripId), [state, tripId]);
  const me = rows?.people.find((p) => p.user_id === ctx.user.id);

  // Balances without the payment being edited, so its own amount isn't counted twice.
  const debts = useMemo(() => {
    if (!rows) return [];
    const ledger = editing ? { ...rows, settlements: rows.settlements.filter((s) => s.id !== editing.id) } : rows;
    return simplifyDebts(balancesFromRows(ledger));
  }, [rows, editing]);

  const initial = useMemo(() => {
    if (editing) {
      return {
        from: editing.from_person_id,
        to: editing.to_person_id,
        currency: editing.currency,
        amount: editing.amount,
        day: dayOf(new Date(editing.settled_at)),
      };
    }
    if (params.from && params.to && params.currency && params.amount) {
      return {
        from: params.from,
        to: params.to,
        currency: params.currency,
        amount: fromMinor(BigInt(params.amount), params.currency),
        day: todayDay(),
      };
    }
    const suggestion = me && rows ? suggestedPayment(balancesFromRows(rows), me.id) : null;
    if (suggestion) {
      return {
        from: suggestion.fromPersonID,
        to: suggestion.toPersonID,
        currency: suggestion.currency,
        amount: fromMinor(suggestion.amount, suggestion.currency),
        day: todayDay(),
      };
    }
    const other = rows?.people.find((p) => p.id !== me?.id && !p.removed_at);
    return { from: me?.id ?? null, to: other?.id ?? null, currency: currencyFor(state, tripId), amount: "", day: todayDay() };
    // Seed once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [from, setFrom] = useState<string | null>(initial.from);
  const [to, setTo] = useState<string | null>(initial.to);
  const [currency, setCurrency] = useState(initial.currency);
  const [amount, setAmount] = useState(initial.amount ? plainAmountString(initial.amount, initial.currency) : "");
  const [edited, setEdited] = useState(!!editing);
  const [day, setDay] = useState(initial.day);
  const [note, setNote] = useState(editing?.note ?? "");
  const [pickingCurrency, setPickingCurrency] = useState(false);
  const [saving, setSaving] = useState(false);

  const people: SelectablePerson[] = useMemo(() => {
    if (!rows) return [];
    const involved = new Set([from, to, ...debts.flatMap((d) => [d.fromUser, d.toUser])]);
    return sortedPeople(
      rows.people.filter((p) => !p.removed_at || involved.has(p.id)),
      me?.id ?? null,
    ).map((p) => ({
      id: p.id,
      name: p.id === me?.id ? "You" : p.display_name,
      avatarName: p.id === me?.id ? ctx.user.displayName : p.display_name,
      email: p.email,
      pending: !p.user_id,
    }));
  }, [rows, me, from, to, debts, ctx.user.displayName]);

  /** The open debt between the chosen pair in this currency, as a fresh draft's amount. */
  function debtBetween(f: string | null, t: string | null, c: string) {
    const forward = debts.find((d) => d.fromUser === f && d.toUser === t && d.currency === c);
    const reverse = debts.find((d) => d.fromUser === t && d.toUser === f && d.currency === c);
    return { forward, reverse };
  }

  function prefill(f: string | null, t: string | null, c: string) {
    if (edited || editing) return;
    const { forward } = debtBetween(f, t, c);
    setAmount(forward ? plainAmountString(forward.amount, c) : "");
  }

  const minor = parseAmountInput(amount, currency);
  const nameOf = (id: string | null) => people.find((p) => p.id === id)?.name ?? "Someone";
  const context = (() => {
    if (!from || !to) return null;
    const { forward, reverse } = debtBetween(from, to, currency);
    if (forward) {
      const owed = formatMoney(forward.amount, currency);
      const head = `${nameOf(from)} ${nameOf(from) === "You" ? "owe" : "owes"} ${nameOf(to)} ${owed}.`;
      if (!minor) return head;
      if (minor < forward.amount) return `${head} After this, ${formatMoney(forward.amount - minor, currency)} will remain.`;
      if (minor === forward.amount) return `${head} This settles the full balance.`;
      return `${head} This overpays by ${formatMoney(minor - forward.amount, currency)}.`;
    }
    if (reverse) {
      return `${nameOf(to)} ${nameOf(to) === "You" ? "owe" : "owes"} ${nameOf(from)} ${formatMoney(reverse.amount, currency)}. This payment goes the opposite way.`;
    }
    return null;
  })();

  const errors = [
    !from || !to ? "Choose who paid and who received it." : null,
    from && from === to ? "Pick two different people." : null,
    amount && (minor === null || minor <= 0n) ? "Enter an amount greater than zero." : null,
  ].filter(Boolean) as string[];
  const canSave = !saving && errors.length === 0 && minor !== null && minor > 0n;

  async function save() {
    if (!canSave || !from || !to || minor === null) return;
    setSaving(true);
    try {
      await saveSettlement(ctx, {
        id: editing?.id,
        tripId,
        fromPersonId: from,
        toPersonId: to,
        amount: fromMinor(minor, currency),
        currency,
        note: note.trim() || null,
        settledAt: settledAtFor(day, editing?.settled_at),
      });
      rememberCurrency(ctx, currency);
      haptics.success();
      router.back();
    } catch (e) {
      setSaving(false);
      Alert.alert("Couldn't save", (e as Error).message);
    }
  }

  if (!rows || !me) {
    return null;
  }

  return (
    <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Stack.Screen
        options={{
          title: editing ? "Edit payment" : "Record a payment",
          headerLeft: () => <HeaderButton title="Cancel" onPress={() => router.back()} />,
          headerRight: () => <HeaderButton title="Save" bold disabled={!canSave} loading={saving} onPress={save} />,
        }}
      />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 40 }}>
        <View style={styles.amountBlock}>
          <AmountInput
            value={amount}
            currency={currency}
            tone={colors.settle}
            autoFocus={!initial.amount}
            onChange={(text) => {
              setAmount(text);
              setEdited(true);
            }}
          />
          <CurrencyPill code={currency} onPress={() => setPickingCurrency(true)} />
        </View>

        <SectionHeader title="Payment" />
        <Card>
          <Row
            title="From"
            right={
              <PersonSelect
                label="Who paid"
                people={people.filter((p) => p.id !== to)}
                value={from}
                onChange={(id) => {
                  setFrom(id);
                  prefill(id, to, currency);
                }}
              />
            }
          />
          <Divider inset={16} />
          <Row
            title="To"
            right={
              <PersonSelect
                label="Who received it"
                people={people.filter((p) => p.id !== from)}
                value={to}
                onChange={(id) => {
                  setTo(id);
                  prefill(from, id, currency);
                }}
              />
            }
          />
        </Card>
        {context && (
          <View style={styles.context}>
            <Icon name="information-circle-outline" size={18} color={colors.settle} />
            <Text style={styles.contextText}>{context}</Text>
          </View>
        )}
        {errors.length > 0 && amount !== "" && <Text style={styles.error}>{errors[0]}</Text>}

        <SectionHeader title="Details" />
        <Card>
          <DateField label="Date" day={day} onChange={setDay} />
          <Divider inset={16} />
          <TextInput
            value={note}
            onChangeText={setNote}
            placeholder="Add a note (optional)"
            placeholderTextColor={colors.textTertiary}
            maxLength={200}
            multiline
            style={styles.note}
          />
        </Card>
        <Text style={styles.hint}>This records money that changed hands outside the app. It doesn't send a payment.</Text>
      </ScrollView>
      <CurrencyPicker
        visible={pickingCurrency}
        value={currency}
        onPick={(code) => {
          setAmount((a) => convertAmountText(a, code));
          setCurrency(code);
          rememberCurrency(ctx, code);
          prefill(from, to, code);
        }}
        onClose={() => setPickingCurrency(false)}
      />
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  amountBlock: { alignItems: "center", paddingTop: 18, paddingBottom: 6, gap: 8 },
  context: {
    flexDirection: "row",
    gap: 8,
    marginHorizontal: PAGE,
    marginTop: -4,
    padding: 12,
    borderRadius: radius.control,
    backgroundColor: "rgba(107,141,166,0.10)",
  },
  contextText: { flex: 1, fontSize: 13, lineHeight: 18, color: colors.text },
  error: { fontSize: 13, color: colors.danger, paddingHorizontal: PAGE + 8, marginTop: 8 },
  note: { minHeight: 52, fontSize: 15, color: colors.text, paddingHorizontal: 16, paddingVertical: 14 },
  hint: { fontSize: 12.5, color: colors.textSecondary, paddingHorizontal: PAGE + 8, marginTop: -6, lineHeight: 17 },
});
