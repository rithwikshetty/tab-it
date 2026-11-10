import { expect, test } from "vitest";
import { timestampUnits } from "./conflict-resolver";
test("postgres microseconds order timestamps within one millisecond", () =>
  expect(timestampUnits("2026-01-01T00:00:00.000001Z") < timestampUnits("2026-01-01T00:00:00.000002Z")).toBe(true));
test("timezone-equivalent stamps are equal", () =>
  expect(timestampUnits("2026-01-01T01:00:00+01:00")).toBe(timestampUnits("2026-01-01T00:00:00Z")));
