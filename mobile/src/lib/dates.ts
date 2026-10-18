// Date labels for the UI, built by hand so they look the same on every
// device and JS engine. Expense dates are calendar days ("2026-06-09");
// everything else is an instant shown in the phone's local time.

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

const pad = (n: number) => String(n).padStart(2, "0");

/** Today's calendar day in local time, as YYYY-MM-DD. */
export function todayDay(): string {
  return dayOf(new Date());
}

/** The local calendar day of a Date, as YYYY-MM-DD. */
export function dayOf(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** A calendar day as a local Date at noon (safe for date pickers). */
export function dayToDate(day: string): Date {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1, 12);
}

/** "9 June 2026" */
export function longDay(day: string): string {
  const [y, m, d] = day.split("-").map(Number);
  return `${d} ${MONTHS[(m ?? 1) - 1]} ${y}`;
}

/** "9 Jun 2026, 09:52" in local time. */
export function dateTime(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS[d.getMonth()]!.slice(0, 3)} ${d.getFullYear()}, ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** "Today", "Yesterday", "Monday 9 Jun", or "9 Jun 2025" for a calendar day. */
export function relativeDay(day: string): string {
  const today = todayDay();
  if (day === today) return "Today";
  const y = new Date();
  y.setDate(y.getDate() - 1);
  if (day === dayOf(y)) return "Yesterday";
  const date = dayToDate(day);
  const short = `${date.getDate()} ${MONTHS[date.getMonth()]!.slice(0, 3)}`;
  return date.getFullYear() === new Date().getFullYear() ? `${WEEKDAYS[date.getDay()]} ${short}` : `${short} ${date.getFullYear()}`;
}

/** The phone's current offset from UTC in minutes, for the domain's calendar maths. */
export function localOffset(date: Date): number {
  return -date.getTimezoneOffset();
}

export function monthShort(day: string): string {
  const [y, m] = day.split("-").map(Number);
  return `${MONTHS[(m ?? 1) - 1]!.slice(0, 3).toLowerCase()} ${y}`;
}
