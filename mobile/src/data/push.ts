import * as Device from "expo-device";
import * as Notifications from "expo-notifications";
import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

import { supabase } from "@/lib/supabase";

// Push notifications. The server sends through APNs only (send-push edge
// function, push_devices.apns_token), so devices register on iOS. Android
// shows activity in the app until the server gains an FCM sender.

export const PUSH_SUPPORTED = Platform.OS === "ios";

const TOKEN_KEY = "push.apnsToken";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

export type PushPermission = "granted" | "denied" | "undetermined" | "unsupported";

export async function pushPermission(): Promise<PushPermission> {
  if (!PUSH_SUPPORTED || !Device.isDevice) return "unsupported";
  const { status, ios } = await Notifications.getPermissionsAsync();
  if (status === "granted" || ios?.status === Notifications.IosAuthorizationStatus.PROVISIONAL) return "granted";
  return status === "denied" ? "denied" : "undetermined";
}

/**
 * Registers this device for the signed-in user. Only shows the system prompt
 * when `prompt` is set; otherwise re-registers silently if already allowed,
 * so token changes and reinstalls heal themselves.
 */
export async function registerForPush(prompt: boolean): Promise<PushPermission> {
  let permission = await pushPermission();
  if (permission === "unsupported") return permission;
  if (permission === "undetermined" && prompt) {
    const result = await Notifications.requestPermissionsAsync({
      ios: { allowAlert: true, allowBadge: true, allowSound: true },
    });
    permission = result.granted ? "granted" : "denied";
  }
  if (permission !== "granted") return permission;
  const token = await Notifications.getDevicePushTokenAsync();
  if (typeof token.data !== "string") return permission;
  const { error } = await supabase.rpc("register_push_device", {
    p_apns_token: token.data,
    p_device_name: Device.deviceName ?? undefined,
  });
  if (!error) await SecureStore.setItemAsync(TOKEN_KEY, token.data);
  return permission;
}

/** Stops this device receiving the user's pushes. Runs before sign-out. */
export async function unregisterPushDevice(userId: string) {
  const token = await SecureStore.getItemAsync(TOKEN_KEY);
  if (!token) return;
  await supabase.from("push_devices").delete().eq("user_id", userId).eq("apns_token", token);
  await SecureStore.deleteItemAsync(TOKEN_KEY);
}

export async function setBadgeCount(count: number) {
  if (!PUSH_SUPPORTED) return;
  await Notifications.setBadgeCountAsync(Math.max(0, count)).catch(() => undefined);
}

export interface PushTarget {
  tripId: string;
  entityType: string | null;
  entityId: string | null;
}

/**
 * Where a tapped push should open. send-push puts `trip_id`, `entity_type` and
 * `entity_id` beside `aps` in the APNs payload; for a remote push iOS exposes
 * that whole payload as the trigger's `payload`, while `content.data` only
 * carries a `body` key.
 */
export function pushTarget(request: Notifications.NotificationRequest): PushTarget | null {
  const trigger = request.trigger;
  const data = (trigger && "payload" in trigger && trigger.payload) || request.content.data;
  const tripId = typeof data?.trip_id === "string" ? data.trip_id.toLowerCase() : null;
  if (!tripId) return null;
  return {
    tripId,
    entityType: typeof data?.entity_type === "string" ? data.entity_type : null,
    entityId: typeof data?.entity_id === "string" ? data.entity_id.toLowerCase() : null,
  };
}
