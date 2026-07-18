import { classifyApnsFailure } from "./apns_response.ts";

function assertEquals<T>(actual: T, expected: T): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("only permanent APNs invalidation marks a token dead", () => {
  assertEquals(classifyApnsFailure(410, "BadDeviceToken"), "token-dead");
  assertEquals(classifyApnsFailure(400, "Unregistered"), "token-dead");
});

Deno.test("BadDeviceToken indicates a likely APNs environment mismatch", () => {
  assertEquals(classifyApnsFailure(400, "BadDeviceToken"), "environment-mismatch");
});

Deno.test("other APNs failures keep the device registration", () => {
  assertEquals(classifyApnsFailure(403, "ExpiredProviderToken"), "other");
  assertEquals(classifyApnsFailure(500, "InternalServerError"), "other");
});
