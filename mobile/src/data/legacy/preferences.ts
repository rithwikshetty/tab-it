import { legacyTimestamp } from "./convert";

export function pendingLegacyActivitySeen(bytes: Uint8Array, userId: string): string | null {
  const key = `sync.pendingActivitySeenAt.${userId.toLowerCase()}`;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const ascii = (start: number, length: number) => Array.from(bytes.subarray(start, start + length), (c) => String.fromCharCode(c)).join("");
  if (ascii(0, 8) !== "bplist00") {
    const xml = ascii(0, bytes.length);
    const start = xml.indexOf(`<key>${key}</key>`);
    const match = start < 0 ? null : /^\s*<date>([^<]+)<\/date>/.exec(xml.slice(start + key.length + 11));
    if (!match?.[1]) return null;
    return new Date(match[1]).toISOString();
  }
  if (bytes.length < 40) throw new Error("Invalid legacy preferences");
  function integer(offset: number, width: number): number {
    if (width < 1 || width > 8 || offset < 0 || offset + width > bytes.length) throw new Error("Invalid plist integer");
    let value = 0n;
    for (let i = 0; i < width; i++) value = value * 256n + BigInt(bytes[offset + i]!);
    if (value > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Oversized plist integer");
    return Number(value);
  }
  const trailer = bytes.length - 32;
  const offsetSize = bytes[trailer + 6]!;
  const refSize = bytes[trailer + 7]!;
  const count = integer(trailer + 8, 8);
  const root = integer(trailer + 16, 8);
  const offsetTable = integer(trailer + 24, 8);
  function object(index: number) {
    if (index >= count) throw new Error("Invalid plist reference");
    return integer(offsetTable + index * offsetSize, offsetSize);
  }
  function length(offset: number) {
    const small = bytes[offset]! & 15;
    if (small !== 15) return { size: small, start: offset + 1 };
    const marker = bytes[offset + 1]!;
    if (marker >> 4 !== 1) throw new Error("Invalid plist length");
    const width = 2 ** (marker & 15);
    return { size: integer(offset + 2, width), start: offset + 2 + width };
  }
  function string(index: number): string | null {
    const offset = object(index);
    const kind = bytes[offset]! >> 4;
    if (kind !== 5 && kind !== 6) return null;
    const { size, start } = length(offset);
    if (kind === 5) return ascii(start, size);
    let value = "";
    for (let i = 0; i < size; i++) value += String.fromCharCode(view.getUint16(start + i * 2));
    return value;
  }
  const offset = object(root);
  if (bytes[offset]! >> 4 !== 13) throw new Error("Legacy preferences are not a dictionary");
  const { size, start } = length(offset);
  for (let i = 0; i < size; i++) {
    if (string(integer(start + i * refSize, refSize)) !== key) continue;
    const date = object(integer(start + (size + i) * refSize, refSize));
    if (bytes[date] !== 0x33) throw new Error("Legacy activity cursor is not a date");
    return legacyTimestamp(view.getFloat64(date + 1));
  }
  return null;
}
