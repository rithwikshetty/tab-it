import { expect, test } from "vitest";
import {
  utcNoonAnchor,
  serializedExpenseDate,
  localDateForPicker,
  localInstant,
  calendarDay,
  displayExpenseDate,
} from "./expense-dates";
test("eveningWestOfUTC", () =>
  expect(
    serializedExpenseDate(
      utcNoonAnchor(localInstant("2026-06-10", -420, 18), -420),
    ),
  ).toBe("2026-06-10"));
test("morningEastOfUTC", () =>
  expect(
    serializedExpenseDate(
      utcNoonAnchor(localInstant("2026-06-10", 600, 8), 600),
    ),
  ).toBe("2026-06-10"));
test("anchorIdempotent", () => {
  const once = utcNoonAnchor(localInstant("2026-06-10", -420, 18), -420);
  expect(utcNoonAnchor(once, -420)).toBe(once);
});
test("anchorMatchesPullConvention", () =>
  expect(utcNoonAnchor(localInstant("2026-12-31", 0, 23), 0)).toBe(
    "2026-12-31T12:00:00.000Z",
  ));
test("displayAndPickerRoundTripAcrossTimezones", () => {
  for (const tz of [840, 765, -660, "UTC"] as const) {
    const anchor = utcNoonAnchor(localInstant("2026-06-10", tz, 8), tz);
    expect(displayExpenseDate(anchor, "yyyy-MM-dd")).toBe("2026-06-10");
    expect(calendarDay(localDateForPicker(anchor, tz), tz)).toBe("2026-06-10");
  }
});
test("UTC offsets are explicit and independent of runtime timezone data", () => {
  expect(calendarDay("2026-06-10T23:00:00Z", "UTC+14:00")).toBe("2026-06-11");
  expect(calendarDay("2026-06-10T01:00:00Z", "-07:00")).toBe("2026-06-09");
  expect(localInstant("2026-06-10", "+12:45", 8)).toBe(
    "2026-06-09T19:15:00.000Z",
  );
  expect(displayExpenseDate("2026-06-10", "full")).toBe(
    "Wednesday, June 10, 2026",
  );
  expect(displayExpenseDate("2026-06-10", "short")).toBe("6/10/26");
  expect(displayExpenseDate("2026-06-10", "EEE, d MMM")).toBe("Wed, 10 Jun");
});
test("offset resolvers handle date-specific DST offsets without Intl", () => {
  const offset = (date: Date) =>
    date.getTime() < Date.parse("2026-03-08T10:00:00Z") ? -480 : -420;
  expect(localInstant("2026-03-08", offset, 0)).toBe(
    "2026-03-08T08:00:00.000Z",
  );
  expect(localInstant("2026-03-08", offset, 12)).toBe(
    "2026-03-08T19:00:00.000Z",
  );
  expect(calendarDay("2026-03-08T07:30:00Z", offset)).toBe("2026-03-07");
});
