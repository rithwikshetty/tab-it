import type * as Notifications from "expo-notifications";
import { expect, it, vi } from "vitest";

import { pushTarget } from "./push";

vi.mock("react-native", () => ({ Platform: { OS: "ios" } }));
vi.mock("expo-device", () => ({}));
vi.mock("expo-secure-store", () => ({}));
vi.mock("expo-notifications", () => ({ setNotificationHandler: vi.fn() }));
vi.mock("@/lib/supabase", () => ({ supabase: {} }));

const TRIP = "6F1C2B9E-0000-4000-8000-000000000001";
const EXPENSE = "6F1C2B9E-0000-4000-8000-000000000002";

function request(trigger: Notifications.NotificationTrigger, data: Record<string, unknown> = {}): Notifications.NotificationRequest {
  return { identifier: "n1", content: { data } as Notifications.NotificationContent, trigger };
}

it("reads the target from a remote push's APNs payload", () => {
  // The shape send-push sends: routing keys beside `aps`, which iOS keeps out of content.data.
  const payload = {
    aps: { alert: { title: "Goa", body: "Sam added Dinner" } },
    trip_id: TRIP,
    entity_type: "expense",
    entity_id: EXPENSE,
  };
  expect(pushTarget(request({ type: "push", payload }))).toEqual({
    tripId: TRIP.toLowerCase(),
    entityType: "expense",
    entityId: EXPENSE.toLowerCase(),
  });
});

it("reads the target from content data when the trigger has no payload", () => {
  expect(pushTarget(request({ type: "push" }, { trip_id: TRIP }))).toEqual({
    tripId: TRIP.toLowerCase(),
    entityType: null,
    entityId: null,
  });
});

it("returns null without a trip", () => {
  expect(pushTarget(request({ type: "push", payload: { aps: {} } }))).toBeNull();
});
