import * as Crypto from "expo-crypto";

/** A new lowercase UUID v4, the form every id and write_id uses. */
export function uuid(): string {
  return Crypto.randomUUID().toLowerCase();
}

export function nowISO(): string {
  return new Date().toISOString();
}
