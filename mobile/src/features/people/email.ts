/** Placeholder emails mark people added without one (e.g. imported from Splitwise). */
export function hasPlaceholderEmail(email: string): boolean {
  return email.endsWith("@users.tab");
}

/** "jo.bloggs@example.com" becomes "Jo Bloggs". */
export function displayNameFromEmail(email: string): string {
  const local = (email.split("@")[0] ?? email).replace(/[._-]+/g, " ").trim();
  const name = local
    .split(" ")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
  return name || email;
}
