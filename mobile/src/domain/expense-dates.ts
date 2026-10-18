export type TimeZoneOffset =
  | number
  | "UTC"
  | "GMT"
  | "Z"
  | `UTC${"+" | "-"}${string}`
  | `${"+" | "-"}${string}`
  | ((instant: Date) => number);
export interface CalendarOptions {
  timeZone?: TimeZoneOffset;
  utcOffsetMinutes?: number | ((instant: Date) => number);
  locale?: string;
}
export const englishMonths = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
] as const;
export const englishWeekdays = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
] as const;
const twoDigits = (value: number) => String(value).padStart(2, "0");
export function calendarOffset(options: CalendarOptions): TimeZoneOffset {
  return options.utcOffsetMinutes ?? options.timeZone ?? "UTC";
}
export function offsetMinutes(
  instant: string | Date,
  offset: TimeZoneOffset = "UTC",
): number {
  const date = new Date(instant);
  if (typeof offset === "function") return offsetMinutes(date, offset(date));
  if (typeof offset === "number") {
    if (!Number.isFinite(offset)) throw new Error("UTC offset must be finite.");
    return offset;
  }
  if (offset === "UTC" || offset === "GMT" || offset === "Z") return 0;
  const match = /^(?:UTC)?([+-])(\d{2}):?(\d{2})$/.exec(offset);
  if (!match || Number(match[2]) > 23 || Number(match[3]) > 59)
    throw new Error(
      "Supply UTC or an explicit UTC offset, not an IANA timezone name.",
    );
  return (
    (Number(match[2]) * 60 + Number(match[3])) * (match[1] === "-" ? -1 : 1)
  );
}
function shiftedDate(instant: string | Date, offset: TimeZoneOffset): Date {
  const date = new Date(instant);
  return new Date(date.getTime() + offsetMinutes(date, offset) * 60_000);
}
function dayString(date: Date): string {
  return `${String(date.getUTCFullYear()).padStart(4, "0")}-${twoDigits(date.getUTCMonth() + 1)}-${twoDigits(date.getUTCDate())}`;
}
export function calendarDay(
  instant: string | Date,
  offset: TimeZoneOffset = "UTC",
): string {
  return dayString(shiftedDate(instant, offset));
}
export function utcNoonAnchor(
  date: string | Date,
  offset: TimeZoneOffset = "UTC",
): string {
  return calendarDay(date, offset) + "T12:00:00.000Z";
}
export function serializedExpenseDate(date: string | Date): string {
  return calendarDay(date, "UTC");
}
export function localInstant(
  day: string,
  offset: TimeZoneOffset = "UTC",
  hour = 12,
): string {
  const desired = new Date(day + "T00:00:00.000Z").getTime() + hour * 3_600_000;
  let result = desired;
  for (let i = 0; i < 4; i++) {
    const next = desired - offsetMinutes(new Date(result), offset) * 60_000;
    if (next === result) break;
    result = next;
  }
  return new Date(result).toISOString();
}
export function localDateForPicker(
  anchored: string | Date,
  offset: TimeZoneOffset = "UTC",
): string {
  return localInstant(serializedExpenseDate(anchored), offset);
}
export function formatCalendarDate(
  instant: string | Date,
  format = "MMM d",
  offset: TimeZoneOffset = "UTC",
): string {
  const date = shiftedDate(instant, offset);
  if (format === "none") return "";
  const month = englishMonths[date.getUTCMonth()]!,
    weekday = englishWeekdays[date.getUTCDay()]!,
    day = date.getUTCDate(),
    year = date.getUTCFullYear();
  if (format === "short")
    return `${date.getUTCMonth() + 1}/${day}/${twoDigits(year % 100)}`;
  const resolved =
    format === "medium"
      ? "MMM d, yyyy"
      : format === "long"
        ? "MMMM d, yyyy"
        : format === "full"
          ? "EEEE, MMMM d, yyyy"
          : format;
  const tokens: Record<string, string> = {
    yyyy: String(year).padStart(4, "0"),
    MMMM: month,
    MMM: month.slice(0, 3),
    MM: twoDigits(date.getUTCMonth() + 1),
    dd: twoDigits(day),
    d: String(day),
    EEEE: weekday,
    EEE: weekday.slice(0, 3),
  };
  return resolved.replace(
    /yyyy|MMMM|MMM|MM|dd|d|EEEE|EEE/g,
    (token) => tokens[token]!,
  );
}
export function displayExpenseDate(
  anchored: string | Date,
  format = "MMM d",
  _locale = "en-US",
): string {
  return formatCalendarDate(anchored, format, "UTC");
}
export function formatClockTime(
  instant: string | Date,
  offset: TimeZoneOffset = "UTC",
  clock: "12h" | "24h" = "12h",
): string {
  const date = shiftedDate(instant, offset),
    hour = date.getUTCHours(),
    minute = twoDigits(date.getUTCMinutes());
  return clock === "24h"
    ? `${twoDigits(hour)}:${minute}`
    : `${hour % 12 || 12}:${minute} ${hour < 12 ? "AM" : "PM"}`;
}
export function dayID(day: string, offset: TimeZoneOffset = "UTC"): string {
  return localInstant(day, offset, 0).replace(".000Z", "Z");
}
export function dayLabel(day: string, _locale = "en-US"): string {
  return displayExpenseDate(day, "MMM d");
}
export const ExpenseDates = {
  utcNoonAnchor,
  serialized: serializedExpenseDate,
  displayString: displayExpenseDate,
  localDateForPicker,
};
