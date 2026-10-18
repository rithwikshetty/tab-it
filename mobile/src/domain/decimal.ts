export interface Rational {
  numerator: bigint;
  denominator: bigint;
}
export function decimalRational(value: string): Rational {
  const match = /^([+-]?)(\d*)(?:\.(\d*))?$/.exec(value.trim());
  if (!match || !(match[2] || match[3]))
    throw new Error(`Invalid decimal: ${value}`);
  const denominator = 10n ** BigInt(match[3]?.length ?? 0);
  const numerator =
    BigInt((match[2] || "0") + (match[3] ?? "")) *
    (match[1] === "-" ? -1n : 1n);
  return { numerator, denominator };
}
export function abs(value: bigint): bigint {
  return value < 0n ? -value : value;
}
export function compare<T extends string | bigint | number>(
  a: T,
  b: T,
): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
export function floorDivide(a: bigint, b: bigint): bigint {
  const q = a / b;
  return a % b !== 0n && a < 0n !== b < 0n ? q - 1n : q;
}
export function roundDivide(
  a: bigint,
  b: bigint,
  mode: "halfAway" | "halfEven" = "halfAway",
): bigint {
  const negative = a < 0n !== b < 0n;
  const n = abs(a),
    d = abs(b),
    q = n / d,
    remainder = n % d;
  const up =
    remainder * 2n > d ||
    (remainder * 2n === d && (mode === "halfAway" || q % 2n !== 0n));
  return (q + (up ? 1n : 0n)) * (negative ? -1n : 1n);
}
export function scaledString(
  value: bigint,
  digits: number,
  fixed = false,
): string {
  const sign = value < 0n ? "-" : "";
  const text = abs(value)
    .toString()
    .padStart(digits + 1, "0");
  if (!digits) return sign + text;
  const whole = text.slice(0, -digits),
    fraction = fixed
      ? text.slice(-digits)
      : text.slice(-digits).replace(/0+$/, "");
  return sign + whole + (fraction ? "." + fraction : "");
}
export function normalizeDecimal(value: string): string {
  const r = decimalRational(value);
  return scaledString(r.numerator, r.denominator.toString().length - 1);
}
export function addDecimals(values: readonly string[]): string {
  const parts = values.map(decimalRational);
  const scale = parts.reduce(
    (a, b) => (a > b.denominator ? a : b.denominator),
    1n,
  );
  return scaledString(
    parts.reduce((a, b) => a + b.numerator * (scale / b.denominator), 0n),
    scale.toString().length - 1,
  );
}
export function subtractDecimals(a: string, b: string): string {
  const r = decimalRational(b);
  return addDecimals([
    a,
    scaledString(-r.numerator, r.denominator.toString().length - 1),
  ]);
}
export function allocateMinor(
  total: bigint,
  ids: readonly string[],
  weights: Readonly<Record<string, string>>,
): Record<string, bigint> {
  const parsed = ids.map((id) => ({ id, ...decimalRational(weights[id]!) }));
  const scale = parsed.reduce(
    (a, b) => (a > b.denominator ? a : b.denominator),
    1n,
  );
  const weighted = parsed.map((p) => ({
    id: p.id,
    weight: p.numerator * (scale / p.denominator),
  }));
  const sum = weighted.reduce((a, b) => a + b.weight, 0n);
  const rows = weighted.map((p) => {
    const base = floorDivide(total * p.weight, sum);
    return { id: p.id, amount: base, remainder: total * p.weight - base * sum };
  });
  let remaining = total - rows.reduce((a, b) => a + b.amount, 0n);
  const order = [...rows].sort(
    (a, b) => compare(b.remainder, a.remainder) || compare(a.id, b.id),
  );
  for (const p of order) {
    if (remaining <= 0n) break;
    p.amount += 1n;
    remaining -= 1n;
  }
  return Object.fromEntries(rows.map((p) => [p.id, p.amount]));
}
