import { utf8Bytes } from "./text";
import type { TripPerson } from "./records";
export type AvatarTone = "terracotta" | "sage" | "sand" | "slate";
const tones: readonly AvatarTone[] = ["terracotta", "sage", "sand", "slate"];
export function avatarTone(id: string): AvatarTone {
  const bytes = id.replace(/-/g, "").match(/../g) ?? [];
  return tones[bytes.reduce((sum, b) => (sum + parseInt(b, 16)) % 256, 0) % 4]!;
}
export function emailAvatarTone(email: string): AvatarTone {
  return tones[utf8Bytes(email).reduce((sum, b) => (sum + b) % 256, 0) % 4]!;
}
/** Joined people take their account's tone and pending people their email's, so a person matches in every trip. */
export function personTone(person: { id: string; user_id?: string | null; email?: string | null }): AvatarTone {
  return person.user_id ? avatarTone(person.user_id) : person.email ? emailAvatarTone(person.email) : avatarTone(person.id);
}
export function nameCharacters(value: string): string[] {
  const points = Array.from(value),
    result: string[] = [];
  let joinNext = false,
    regionalCount = 0;
  for (const point of points) {
    const code = point.codePointAt(0)!;
    const regional = code >= 0x1f1e6 && code <= 0x1f1ff;
    const extender = /\p{M}/u.test(point) || code === 0xfe0e || code === 0xfe0f || (code >= 0x1f3fb && code <= 0x1f3ff);
    if (result.length && (extender || joinNext || point === "\u200d" || (regional && regionalCount % 2 === 1)))
      result[result.length - 1] += point;
    else result.push(point);
    joinNext = point === "\u200d";
    regionalCount = regional ? regionalCount + 1 : 0;
  }
  return result;
}
export function avatarInitial(displayName: string): string {
  return nameCharacters(displayName.trim())[0]?.toUpperCase() ?? "?";
}
export function compareNames(a: string, b: string): number {
  const lhs = a.toLowerCase().normalize("NFD"),
    rhs = b.toLowerCase().normalize("NFD");
  const baseA = lhs.replace(/\p{M}/gu, ""),
    baseB = rhs.replace(/\p{M}/gu, "");
  return baseA < baseB ? -1 : baseA > baseB ? 1 : lhs < rhs ? -1 : lhs > rhs ? 1 : 0;
}
export function sortedPeople(people: readonly TripPerson[], currentPersonID: string | null = null): TripPerson[] {
  return [...people].sort((a, b) =>
    a.id === b.id
      ? 0
      : a.id === currentPersonID
        ? -1
        : b.id === currentPersonID
          ? 1
          : (a.joined_at !== null) !== (b.joined_at !== null)
            ? a.joined_at !== null
              ? -1
              : 1
            : compareNames(a.display_name, b.display_name),
  );
}
export function normalizedEmail(value: string): string {
  return value.trim().toLowerCase();
}
export function isValidEmail(value: string): boolean {
  const email = normalizedEmail(value),
    at = email.indexOf("@"),
    domain = email.slice(at + 1);
  return !email.includes("|") && at > 0 && domain.includes(".") && !domain.endsWith(".");
}
export function inviteJoinErrorMessage(code: string | null): string | null {
  return code === "22023"
    ? "Your account doesn't have a verified email. Verify your email, then open the invite link again."
    : code === "P0002" || code === "42501"
      ? "This invite link is invalid or was turned off."
      : null;
}
export const EmailValidator = {
  normalized: normalizedEmail,
  isValid: isValidEmail,
};
export const AvatarInitial = { from: avatarInitial };
export const AvatarTone = {
  deterministic: avatarTone,
  forEmail: emailAvatarTone,
};
export const InviteJoinErrorMessage = { message: inviteJoinErrorMessage };
export const DefaultCategories = {
  food: {
    id: "00000001-0000-0000-0000-000000000000",
    name: "Food & Drink",
    icon: "bowl-food",
  },
  transport: {
    id: "00000002-0000-0000-0000-000000000000",
    name: "Transport",
    icon: "car-profile",
  },
  lodging: {
    id: "00000003-0000-0000-0000-000000000000",
    name: "Lodging",
    icon: "bed",
  },
  activities: {
    id: "00000004-0000-0000-0000-000000000000",
    name: "Activities",
    icon: "mask-happy",
  },
  shopping: {
    id: "00000005-0000-0000-0000-000000000000",
    name: "Shopping",
    icon: "shopping-bag",
  },
  other: {
    id: "00000006-0000-0000-0000-000000000000",
    name: "Other",
    icon: "tag",
  },
};
export const defaultCategories = Object.values(DefaultCategories);
export function activePeople(people: readonly TripPerson[]): TripPerson[] {
  return people.filter((p) => p.removed_at === null);
}
export function hasPlaceholderEmail(person: Pick<TripPerson, "email">): boolean {
  return person.email.endsWith("@users.tab");
}
export function isNonGroup(trip: { kind: string }): boolean {
  return trip.kind === "non_group";
}
export function primaryPayerID(
  payments: readonly {
    trip_person_id: string;
  }[],
): string | null {
  return payments.map((p) => p.trip_person_id).sort()[0] ?? null;
}
export function effectiveSplitType(value: string): import("./records").SplitType {
  return ["equal", "exact", "percentage", "shares", "adjustment"].includes(value) ? (value as import("./records").SplitType) : "equal";
}
export function effectivePaymentMethod(value: string): import("./records").PaymentMethod {
  return value === "cash" || value === "bank_transfer" ? value : "card";
}
export function categoryOption(category: { id: string; icon: string; name: string }): {
  id: string;
  icon: string;
  name: string;
} {
  return { id: category.id, icon: category.icon, name: category.name };
}
