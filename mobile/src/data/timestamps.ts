// Postgres returns timestamptz with microsecond precision
// ("2026-10-18T03:26:11.245123+00:00"); JavaScript dates stop at
// milliseconds. Conflict resolution must order timestamps exactly as the
// server does, so comparisons use integer microseconds since the epoch.

const ISO = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}(?::?\d{2})?)?$/;

export function toMicros(iso: string): bigint {
  const m = ISO.exec(iso.trim());
  if (!m) {
    const ms = Date.parse(iso);
    if (Number.isNaN(ms)) throw new Error(`Invalid timestamp: ${iso}`);
    return BigInt(ms) * 1000n;
  }
  const [, date, time, fraction = "", zone = "Z"] = m;
  const offset = zone === "Z" ? "Z" : zone.length === 3 ? `${zone}:00` : zone.includes(":") ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`;
  const seconds = Date.parse(`${date}T${time}${offset}`);
  if (Number.isNaN(seconds)) throw new Error(`Invalid timestamp: ${iso}`);
  const micros = BigInt((fraction + "000000").slice(0, 6));
  return BigInt(seconds) * 1000n + micros;
}

export function compareTimestamps(a: string, b: string): number {
  const x = toMicros(a);
  const y = toMicros(b);
  return x < y ? -1 : x > y ? 1 : 0;
}

export function maxTimestamp(a: string, b: string): string {
  return compareTimestamps(a, b) >= 0 ? a : b;
}
