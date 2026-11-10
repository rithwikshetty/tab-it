import { router, useFocusEffect } from "expo-router";
import { memo, useCallback, useMemo, useRef, useState } from "react";
import {
  Pressable,
  RefreshControl,
  SectionList,
  StyleSheet,
  Text,
  View,
  type SectionListData,
  type SectionListRenderItemInfo,
} from "react-native";
import ReanimatedSwipeable, { type SwipeableMethods } from "react-native-gesture-handler/ReanimatedSwipeable";
import { SafeAreaView } from "react-native-safe-area-context";

import { markActivityRead, markActivitySeen } from "@/data/actions";
import { activityOptions } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";
import { activityNavigation, activitySections, type ActivityTarget } from "@/domain";
import { haptics } from "@/ui/haptics";
import { Card, Divider, EmptyState, Icon, LargeTitle, sameValues, SectionHeader, type IconName, useTabBarClearance } from "@/ui/primitives";
import { colors, type } from "@/ui/theme";

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
type Section = { dateLabel: string; data: readonly Row[] };

const rowKey = (row: Row) => row.id;
const renderSectionHeader = ({ section }: { section: SectionListData<Row, Section> }) => <SectionHeader title={section.dateLabel} />;

export default function Activity() {
  const ctx = useSignedIn();
  const state = useAppState();
  const [refreshing, setRefreshing] = useState(false);
  const clearance = useTabBarClearance();
  const options = useMemo(() => activityOptions(state, ctx.user.id), [state, ctx.user.id]);
  const sections = useMemo(
    () =>
      activitySections([...state.tables.activity_log.values()], options, new Date().toISOString()).map((s) => ({
        ...s,
        key: s.id,
        data: s.rows,
      })),
    [state, options],
  );
  const hasUnread = sections.some((s) => s.rows.some((r) => r.isUnread));
  const unreadRef = useRef(hasUnread);
  unreadRef.current = hasUnread;
  const stateRef = useRef(state);
  stateRef.current = state;

  useFocusEffect(
    useCallback(() => {
      // Returning to the tab pulls unless a full pull has just finished.
      const last = ctx.sync.getStatus().lastPulledAt;
      if (!last || Date.now() - last.getTime() > 30_000) void ctx.sync.request({ pull: true });
      // Leaving the tab marks everything seen, so dots stay visible while reading.
      return () => {
        if (unreadRef.current) void markActivitySeen(ctx);
      };
    }, [ctx]),
  );

  const open = useCallback(
    (row: Row) => {
      haptics.light();
      void markActivityRead(ctx, row.id);
      const t = stateRef.current.tables;
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
    },
    [ctx],
  );
  const read = useCallback((id: string) => void markActivityRead(ctx, id), [ctx]);
  const dismiss = useCallback((id: string) => void markActivityRead(ctx, id, true), [ctx]);
  const renderItem = useCallback(
    ({ item, index, section }: SectionListRenderItemInfo<Row, Section>) => (
      <ActivityItem
        row={item}
        first={index === 0}
        last={index === section.data.length - 1}
        onOpen={open}
        onRead={read}
        onDismiss={dismiss}
      />
    ),
    [open, read, dismiss],
  );

  return (
    <SafeAreaView style={styles.fill} edges={["top"]}>
      <SectionList
        sections={sections}
        keyExtractor={rowKey}
        renderItem={renderItem}
        renderSectionHeader={renderSectionHeader}
        stickySectionHeadersEnabled={false}
        contentContainerStyle={{ paddingBottom: clearance + 24 }}
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
        ListHeaderComponent={<LargeTitle title="Activity" />}
        ListEmptyComponent={
          <EmptyState icon="notifications-outline" title="No activity yet" message="Updates from your trips show up here." />
        }
      />
    </SafeAreaView>
  );
}

/** One activity row, sliced from its day's card; re-renders only when the values it shows change. */
const ActivityItem = memo(function ActivityItem({
  row,
  first,
  last,
  onOpen,
  onRead: markRead,
  onDismiss: markDismissed,
}: {
  row: Row;
  first: boolean;
  last: boolean;
  onOpen: (row: Row) => void;
  onRead: (id: string) => void;
  onDismiss: (id: string) => void;
}) {
  const ref = useRef<SwipeableMethods>(null);
  const tint = row.isNegative ? colors.warning : colors.accentStrong;
  const onPress = () => onOpen(row);
  const onRead = () => markRead(row.id);
  const onDismiss = () => markDismissed(row.id);
  return (
    <Card first={first} last={last}>
      {!first && <Divider inset={68} />}
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
    </Card>
  );
}, sameValues);

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 14, paddingVertical: 12, backgroundColor: colors.surface },
  icon: { width: 42, height: 42, borderRadius: 21, alignItems: "center", justifyContent: "center" },
  title: { fontSize: 15, color: colors.text, lineHeight: 20 },
  meta: { fontSize: 12.5, color: colors.textSecondary, marginTop: 2 },
  amount: type.amount,
  time: { fontSize: 12, color: colors.textSecondary, fontVariant: ["tabular-nums"] },
  dot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.accent },
  action: { width: 84, alignItems: "center", justifyContent: "center", gap: 2 },
  actionText: { color: "#fff", fontSize: 12, fontWeight: "600" },
});
