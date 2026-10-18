import { expect, test } from "vitest";
import {
  resolveConflict as resolve,
  mergeDecision as merge,
  type Versioned,
} from "./conflict-resolver";
const low = "00000000-0000-0000-0000-00000000000a",
  high = "ffffffff-ffff-ffff-ffff-ffffffffffff",
  t0 = "2023-11-14T22:13:20Z";
const time = (seconds: number) =>
  new Date(Date.parse(t0) + seconds * 1000).toISOString();
const v = (
  value: string,
  seconds = 0,
  writeID = low,
  deletedAt: string | null = null,
): Versioned<string> => ({
  value,
  updatedAt: time(seconds),
  writeID,
  deletedAt,
});
test("bothAliveLaterWins", () =>
  expect(resolve(v("old"), v("new", 60)).value).toBe("new"));
test("bothAliveTiebreakerWriteID", () =>
  expect(resolve(v("a-value"), v("b-value", 0, high)).value).toBe("b-value"));
test("bothAliveFullTie", () =>
  expect(resolve(v("a-value"), v("b-value")).value).toBe("a-value"));
test("deletedWinsOverNewerEdit", () => {
  const alive = v("edited", 3600, high),
    deleted = v("tombstone", 0, low, t0);
  expect(resolve(alive, deleted).value).toBe("tombstone");
  expect(resolve(deleted, alive).value).toBe("tombstone");
});
test("bothDeletedLaterWins", () =>
  expect(resolve(v("v1", 0, low, t0), v("v2", 0, low, time(60))).value).toBe(
    "v2",
  ));
test("bothDeletedTiebreaker", () =>
  expect(
    resolve(v("a-tombstone", 0, low, t0), v("b-tombstone", 0, high, t0)).value,
  ).toBe("b-tombstone"));
test("orderIndependent", () => {
  const a = v("old"),
    b = v("new", 60);
  expect(resolve(a, b).value).toBe("new");
  expect(resolve(b, a).value).toBe("new");
});
test("orderIndependentForTiebreaker", () => {
  const a = v("a"),
    b = v("b", 0, high);
  expect(resolve(a, b).value).toBe("b");
  expect(resolve(b, a).value).toBe("b");
});
test("mergeCleanLocalAppliesRemote", () =>
  expect(merge(v("local", 60, high), false, v("remote"))).toBe("applyRemote"));
test("mergeDirtyNewerLocalSurvives", () =>
  expect(merge(v("local", 60), true, v("remote", 0, high))).toBe("keepLocal"));
test("mergeDirtyOlderLocalYields", () =>
  expect(merge(v("local", 0, high), true, v("remote", 60))).toBe(
    "applyRemote",
  ));
test("mergeRemoteDeleteBeatsDirtyEdit", () =>
  expect(merge(v("local", 3600, high), true, v("remote", 0, low, t0))).toBe(
    "applyRemote",
  ));
test("mergeLocalDeleteBeatsNewerRemoteEdit", () =>
  expect(merge(v("local", 0, low, t0), true, v("remote", 3600, high))).toBe(
    "keepLocal",
  ));
test("mergeSameWriteIDKeepsLocal", () =>
  expect(merge(v("local"), true, v("remote", 60))).toBe("keepLocal"));
test("postgres microseconds decide before UUID ties", () => {
  const a = { ...v("a", 0, high), updatedAt: "2026-01-01T00:00:00.000001Z" },
    b = { ...v("b"), updatedAt: "2026-01-01T00:00:00.000002Z" };
  expect(resolve(a, b)).toBe(b);
});
test("timezone-equivalent stamps reach the write ID tie-breaker", () =>
  expect(
    resolve(
      { ...v("a"), updatedAt: "2026-01-01T01:00:00+01:00" },
      { ...v("b", 0, high), updatedAt: "2026-01-01T00:00:00Z" },
    ).value,
  ).toBe("b"));
