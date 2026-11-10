export function timestampUnits(value: string): bigint {
  const match = /\.(\d+)(?=Z|[+-]\d\d:\d\d$)/i.exec(value);
  const instant = match ? value.replace("." + match[1], "") : value;
  return BigInt(Date.parse(instant)) * 1000000n + BigInt((match?.[1] ?? "").padEnd(9, "0").slice(0, 9) || "0");
}
