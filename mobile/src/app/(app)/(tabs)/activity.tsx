import { router, useFocusEffect } from "expo-router";
import { useCallback, useMemo, useRef, useState } from "react";
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import ReanimatedSwipeable, { type SwipeableMethods } from "react-native-gesture-handler/ReanimatedSwipeable";
import { SafeAreaView } from "react-native-safe-area-context";

import { markActivityRead, markActivitySeen } from "@/data/actions";
import { activityOptions } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { activityNavigation, activitySections, type ActivityTarget } from "@/domain";
import { haptics } from "@/ui/haptics";
import { Card, Divider, EmptyState, Icon, LargeTitle, SectionHeader, type IconName } from "@/ui/primitives";
import { colors } from "@/ui/theme";

/** The presenter names SF Symbols; these are their Ionicons equivalents. */
const ICONS: Record<string, IconName> = {
  "plus.circle.fill": "add-circle",
  "pencil.circle.fill": "create",
  pencil: "create",
  "trash.circle.fill": "trash",
  "arrow.left.arrow.right.circle.fill": "swap-horizontal",
  "person.crop.circle.badge.plus": "person-add",
  "person.crop.circle.badge.minus": "person-remove",
  "suitcase.fill": "airplane",
  "bell.fill": "notifications",
};

type Row = ReturnType<typeof activitySections>[number]["rows"][number];

export default function Activity() {
  const ctx = useSignedIn();
  const state = useAppState();
  const [refreshing, setRefreshing] = useState(false);
  const options = useMemo(() => activityOptions(state, ctx.user.id), [state, ctx.user.id]);
  const sections = useMemo(
    () => activitySections([...state.tables.activity_log.values()], options, new Date().toISOString()),
    [state, options],
  );
  const hasUnread = sections.some((s) => s.rows.some((r) => r.isUnread));
  const unreadRef = useRef(hasUnread);
  unreadRef.current = hasUnread;

  useFocusEffect(
    useCallback(() => {
      void ctx.sync.request({ pull: true });
      // Leaving the tab marks everything seen, so dots stay visible while reading.
      return () => {
        if (unreadRef.current) void markActivitySeen(ctx);
      };
    }, [ctx]),
  );

  function open(row: Row) {
    haptics.light();
    void markActivityRead(ctx, row.id);
    const t = state.tables;
    const stack = activityNavigation(
      row.target as ActivityTarget,
      (id) => !!t.expenses.get(id) && !t.expenses.get(id)!.deleted_at,
      (id) => !!t.settlements.get(id) && !t.settlements.get(id)!.deleted_at,
    );
    const last = stack[stack.length - 1];
    if (!last) return;
    if (last.type === "expense") router.push({ pathname: "/expense/[id]", params: { id: last.id } });
    else if (last.type === "settlement") router.push({ pathname: "/settlement/[id]", params: { id: last.id } });
    else router.push({ pathname: "/trip/[id]", params: { id: last.id } });
  }

  return (
    <SafeAreaView style={styles.fill} edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 40 }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            tintColor={colors.accent}
            colors={[colors.accent]}
            onRefresh={async () => {
              setRefreshing(true);
              await ctx.sync.refresh();
              setRefreshing(false);
            }}
          />
        }
      >
        <LargeTitle title="Activity" />
        {sections.length === 0 ? (
          <EmptyState icon="notifications-outline" title="No activity yet" message="Updates from your trips show up here." />
        ) : (
          sections.map((section) => (
            <View key={section.id}>
              <SectionHeader title={section.dateLabel} />
              <Card>
                {section.rows.map((row, i) => (
                  <View key={row.id}>
                    {i > 0 && <Divider inset={68} />}
                    <ActivityItem
                      row={row}
                      onPress={() => open(row)}
                      onRead={() => markActivityRead(ctx, row.id)}
                      onDismiss={() => markActivityRead(ctx, row.id, true)}
                    />
                  </View>
                ))}
              </Card>
            </View>
          ))
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function ActivityItem({ row, onPress, onRead, onDismiss }: { row: Row; onPress: () => void; onRead: () => void; onDismiss: () => void }) {
  const ref = useRef<SwipeableMethods>(null);
  const tint = row.isNegative ? colors.warning : colors.accentStrong;
  return (
    <ReanimatedSwipeable
      ref={ref}
      friction={2}
      overshootLeft={false}
      overshootRight={false}
      renderLeftActions={
        row.isUnread
          ? () => (
              <Pressable
                style={[styles.action, { backgroundColor: colors.accent }]}
                onPress={() => {
                  ref.current?.close();
                  onRead();
                }}
                accessibilityRole="button"
              >
                <Icon name="checkmark-done" size={20} color="#fff" />
                <Text style={styles.actionText}>Read</Text>
              </Pressable>
            )
          : undefined
      }
      renderRightActions={() => (
        <Pressable
          style={[styles.action, { backgroundColor: colors.danger }]}
          onPress={() => {
            ref.current?.close();
            onDismiss();
          }}
          accessibilityRole="button"
        >
          <Icon name="eye-off-outline" size={20} color="#fff" />
          <Text style={styles.actionText}>Hide</Text>
        </Pressable>
      )}
    >
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${row.isUnread ? "Unread. " : ""}${row.title}. ${row.tripName}. ${row.trailing ?? ""} ${row.timeText}`}
        accessibilityActions={[
          { name: "magicTap" },
          ...(row.isUnread ? [{ name: "read", label: "Mark as read" }] : []),
          { name: "dismiss", label: "Hide" },
        ]}
        onAccessibilityAction={(e) =>
          e.nativeEvent.actionName === "read" ? onRead() : e.nativeEvent.actionName === "dismiss" ? onDismiss() : onPress()
        }
        onPress={onPress}
        style={({ pressed }) => [
          styles.row,
          row.isUnread && { backgroundColor: "#FBFCF8" },
          pressed && { backgroundColor: colors.surface2 },
        ]}
      >
        <View style={[styles.icon, { backgroundColor: row.isNegative ? "#F6E9DE" : colors.accentTint }]}>
          <Icon name={ICONS[row.icon] ?? "ellipse"} size={18} color={tint} />
        </View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={[styles.title, row.isUnread && { fontWeight: "600" }]} numberOfLines={2}>
            {row.title}
          </Text>
          <Text style={styles.meta} numberOfLines={1}>
            {[row.tripName, row.detail].filter(Boolean).join(" · ")}
          </Text>
        </View>
        <View style={{ alignItems: "flex-end", gap: 2 }}>
          {row.trailing && (
            <Text style={[styles.amount, row.isNegative && { color: colors.textSecondary, textDecorationLine: "line-through" }]}>
              {row.trailing}
            </Text>
          )}
          <Text style={styles.time}>{row.timeText}</Text>
        </View>
        {row.isUnread ? <View style={styles.dot} /> : <View style={{ width: 8 }} />}
      </Pressable>
    </ReanimatedSwipeable>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 14, paddingVertical: 12, backgroundColor: colors.surface },
  icon: { width: 42, height: 42, borderRadius: 21, alignItems: "center", justifyContent: "center" },
  title: { fontSize: 15, color: colors.text, lineHeight: 20 },
  meta: { fontSize: 12.5, color: colors.textSecondary, marginTop: 2 },
  amount: { fontSize: 15, fontWeight: "600", color: colors.text, fontVariant: ["tabular-nums"] },
  time: { fontSize: 12, color: colors.textSecondary, fontVariant: ["tabular-nums"] },
  dot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.accent },
  action: { width: 84, alignItems: "center", justifyContent: "center", gap: 2 },
  actionText: { color: "#fff", fontSize: 12, fontWeight: "600" },
});
