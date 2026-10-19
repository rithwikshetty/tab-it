import * as Notifications from "expo-notifications";
import { router, Stack } from "expo-router";
import { useEffect, useRef } from "react";
import { Alert, AppState } from "react-native";

import { savePendingInvite, takePendingInvite } from "@/data/invites";
import { inviteErrorMessage, joinTripWithInvite } from "@/data/online";
import { toRemoteError } from "@/data/remote";
import { pushTarget, registerForPush, setBadgeCount } from "@/data/push";
import { useSignedIn } from "@/data/session";
import { useUnreadActivityCount } from "@/features/activity/use-unread";
import { colors } from "@/ui/theme";

export default function SignedInLayout() {
  usePendingInvite();
  usePush();
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.bg },
        headerShadowVisible: false,
        headerTintColor: colors.accentStrong,
        headerTitleStyle: { color: colors.text, fontWeight: "600", fontSize: 16 },
        headerBackButtonDisplayMode: "minimal",
        headerTitleAlign: "center",
        contentStyle: { backgroundColor: colors.bg },
      }}
    >
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="trip/[id]" options={{ title: "" }} />
      <Stack.Screen name="expense/[id]" options={{ title: "" }} />
      <Stack.Screen name="settlement/[id]" options={{ title: "" }} />
      <Stack.Screen name="friend/[key]" options={{ title: "" }} />
      <Stack.Screen name="new-trip" options={{ presentation: "modal", title: "New trip" }} />
      <Stack.Screen name="new-expense" options={{ presentation: "modal", title: "New expense" }} />
      <Stack.Screen name="expense-form" options={{ presentation: "modal", title: "" }} />
      <Stack.Screen name="settle-up" options={{ presentation: "modal", title: "Record a payment" }} />
      <Stack.Screen name="trip-people" options={{ presentation: "modal", title: "People" }} />
      <Stack.Screen name="import-splitwise" options={{ presentation: "modal", title: "Import from Splitwise" }} />
      <Stack.Screen name="trip-edit" options={{ presentation: "modal", title: "Edit trip" }} />
      <Stack.Screen name="sync-issues" options={{ presentation: "modal", title: "Unsynced changes" }} />
    </Stack>
  );
}

/** Redeems an invite link that arrived before or during this session. */
function usePendingInvite() {
  const ctx = useSignedIn();
  const busy = useRef(false);
  useEffect(() => {
    const redeem = async () => {
      if (busy.current) return;
      busy.current = true;
      const token = await takePendingInvite();
      try {
        if (!token) return;
        const { tripId } = await joinTripWithInvite(ctx, token);
        router.push({ pathname: "/trip/[id]", params: { id: tripId } });
      } catch (error) {
        // Offline: keep the invite and try again on the next return to the app.
        if (token && toRemoteError(error).transient) await savePendingInvite(token);
        else Alert.alert("Can't join trip", inviteErrorMessage(error));
      } finally {
        busy.current = false;
      }
    };
    void redeem();
    const sub = AppState.addEventListener("change", (s) => s === "active" && void redeem());
    return () => sub.remove();
  }, [ctx]);
}

function usePush() {
  const ctx = useSignedIn();
  const unread = useUnreadActivityCount();
  const handled = useRef<string | null>(null);

  useEffect(() => {
    // The first prompt waits until the user has a trip, when notifications
    // obviously help; after that it only re-registers silently.
    const hasTrips = [...ctx.store.getState().tables.trips.values()].some((t) => !t.deleted_at && t.kind === "trip");
    void registerForPush(hasTrips).catch(() => undefined);
    const sub = AppState.addEventListener("change", (s) => s === "active" && void registerForPush(false).catch(() => undefined));
    return () => sub.remove();
  }, [ctx]);

  useEffect(() => {
    void setBadgeCount(unread);
  }, [unread]);

  useEffect(() => {
    const received = Notifications.addNotificationReceivedListener(() => ctx.sync.request({ pull: true }));
    return () => received.remove();
  }, [ctx]);

  useEffect(() => {
    // A tap that launched the app waits as the last response; later taps come
    // through the listener. Expo keeps every tap as the last response, so each
    // one is cleared once seen or a remount after sign-in would reopen it.
    // send-push collapses by entity, so pushes about the same expense share an
    // identifier and the delivery date tells them apart.
    let active = true;
    const open = (response: Notifications.NotificationResponse) => {
      Notifications.clearLastNotificationResponse();
      const key = `${response.notification.request.identifier}:${response.notification.date}`;
      if (handled.current === key) return;
      handled.current = key;
      const target = pushTarget(response.notification.request);
      if (!target) return;
      void (async () => {
        await ctx.sync.request({ tripId: target.tripId });
        if (!active) return;
        const t = ctx.store.getState().tables;
        router.push({ pathname: "/trip/[id]", params: { id: target.tripId } });
        if (target.entityType === "expense" && target.entityId && t.expenses.get(target.entityId)?.deleted_at === null) {
          router.push({ pathname: "/expense/[id]", params: { id: target.entityId } });
        } else if (target.entityType === "settlement" && target.entityId && t.settlements.get(target.entityId)?.deleted_at === null) {
          router.push({ pathname: "/settlement/[id]", params: { id: target.entityId } });
        }
      })();
    };
    const launched = Notifications.getLastNotificationResponse();
    if (launched) open(launched);
    const tapped = Notifications.addNotificationResponseReceivedListener(open);
    return () => {
      active = false;
      tapped.remove();
    };
  }, [ctx]);
}
