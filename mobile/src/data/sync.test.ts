import { beforeEach, expect, it, vi } from "vitest";

import { TABLE_NAMES, type State } from "./schema";
import type { Store } from "./store";
import { SyncEngine } from "./sync";

const mocks = vi.hoisted(() => ({
  calls: [] as string[],
  claim: vi.fn(),
  fetchSnapshot: vi.fn(),
}));

vi.mock("react-native", () => ({ AppState: { currentState: "active", addEventListener: vi.fn() } }));
vi.mock("expo-network", () => ({ addNetworkStateListener: vi.fn() }));
vi.mock("@/lib/ids", () => ({ uuid: () => "00000000-0000-0000-0000-000000000000" }));
vi.mock("./receipts", () => ({ uploadPendingReceipts: vi.fn() }));
vi.mock("./merge", () => ({ adoptServerPerson: vi.fn(), GONE: "gone", mergeRemote: () => [] }));
vi.mock("@/lib/supabase", () => ({
  supabase: {
    rpc: (name: string) => {
      mocks.calls.push(name);
      return name === "claim_trip_people_for_current_email" ? mocks.claim() : Promise.resolve({ data: null, error: null });
    },
  },
}));
vi.mock("./remote", async (original) => ({
  ...(await original<typeof import("./remote")>()),
  fetchSnapshot: (tripId?: string) => {
    mocks.calls.push(tripId ? `snapshot:${tripId}` : "snapshot");
    return mocks.fetchSnapshot();
  },
}));

function engine() {
  const state: State = {
    tables: Object.fromEntries(TABLE_NAMES.map((t) => [t, new Map()])) as unknown as State["tables"],
    meta: new Map(),
  };
  const store = { getState: () => state, commit: vi.fn(async () => {}), subscribe: () => () => {} } as unknown as Store;
  return new SyncEngine(store, { id: "user", email: "me@x.test", displayName: "Me" });
}

beforeEach(() => {
  mocks.calls.length = 0;
  mocks.claim.mockResolvedValue({ data: [], error: null });
  mocks.fetchSnapshot.mockResolvedValue({ snapshot: {}, errors: [] });
});

it("claims trip people pending under the account's email before every full pull", async () => {
  const sync = engine();
  await sync.request({ pull: true });
  await sync.refresh();
  expect(mocks.calls.filter((c) => c === "claim_trip_people_for_current_email" || c === "snapshot")).toEqual([
    "claim_trip_people_for_current_email",
    "snapshot",
    "claim_trip_people_for_current_email",
    "snapshot",
  ]);
});

it("does not claim before a single trip's pull", async () => {
  await engine().request({ tripId: "trip" });
  expect(mocks.calls).toContain("snapshot:trip");
  expect(mocks.calls).not.toContain("claim_trip_people_for_current_email");
});

it("still pulls when the claim fails", async () => {
  mocks.claim.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
  const sync = engine();
  await sync.request({ pull: true });
  expect(mocks.calls).toContain("snapshot");
  expect(sync.getStatus().phase).toBe("idle");
});
