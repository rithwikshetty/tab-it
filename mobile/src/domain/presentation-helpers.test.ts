import { expect, test } from "vitest";
import {
  isValidEmail,
  normalizedEmail,
  inviteJoinErrorMessage,
  avatarInitial,
  avatarTone,
  emailAvatarTone,
  personTone,
  sortedPeople,
} from "./presentation-helpers";
import {
  normalizedAuthEmail,
  visibleEmail,
  isApplePrivateRelayEmail,
  fallbackDisplayName,
  normalizedDisplayName,
  normalizedVerificationCode,
  emailVerificationCodeLength,
  isExpectedAuthCallbackURL,
  inviteToken,
} from "./auth-helpers";
import { splitwiseCategoryID, bestSelfMatch, mapSplitwiseRows } from "./splitwise-importer";
import { parseSplitwise } from "./splitwise-import";
import { a, b, c, person, now } from "./test-support";
import { DefaultCategories as D } from "./presentation-helpers";
test("acceptsNormal", () => {
  for (const email of ["alice@example.com", "alex@example.com", "Alex+test@sub.example.co.uk", " alex@example.com "])
    expect(isValidEmail(email)).toBe(true);
});
test("rejectsNoDot", () => {
  expect(isValidEmail("a@b")).toBe(false);
  expect(isValidEmail("alex@localhost")).toBe(false);
});
test("rejectsMalformed", () => {
  for (const email of ["", "alex", "@example.com", "alex@example."]) expect(isValidEmail(email)).toBe(false);
});
test("rejectsPipe", () => {
  expect(isValidEmail("b@b.com|c@c.com")).toBe(false);
  expect(isValidEmail("alex|bob@example.com")).toBe(false);
});
test("normalizes", () => {
  expect(isValidEmail("  Alice@Example.COM  ")).toBe(true);
  expect(normalizedEmail("  Alex@EXAMPLE.COM\n")).toBe("alex@example.com");
});
test("missingVerifiedEmailExplainsHowToJoin", () =>
  expect(inviteJoinErrorMessage("22023")).toBe(
    "Your account doesn't have a verified email. Verify your email, then open the invite link again.",
  ));
test("invalidOrDisabledInviteErrorsKeepTheirMessage", () => {
  expect(inviteJoinErrorMessage("P0002")).toBe("This invite link is invalid or was turned off.");
  expect(inviteJoinErrorMessage("42501")).toBe("This invite link is invalid or was turned off.");
});
test("missingPostgresCodeHasNoMappedMessage", () => expect(inviteJoinErrorMessage(null)).toBeNull());
test("unrelatedPostgresCodeHasNoMappedMessage", () => expect(inviteJoinErrorMessage("23505")).toBeNull());
test("categoryMapping", () => {
  for (const [source, target] of [
    ["Taxi", D.transport.id],
    ["Bus/train", D.transport.id],
    ["Liquor", D.food.id],
    ["Groceries", D.food.id],
    ["Hotel", D.lodging.id],
    ["Games", D.activities.id],
    ["Electronics", D.shopping.id],
  ])
    expect(splitwiseCategoryID(source!)).toBe(target);
});
test("categoryFallback", () => {
  for (const source of ["General", "Something Splitwise Invented", ""]) expect(splitwiseCategoryID(source)).toBe(D.other.id);
});
test("categoryNormalization", () => expect(splitwiseCategoryID("  taxi ")).toBe(D.transport.id));
test("selfMatchExact", () => expect(bestSelfMatch(["Rithwik Shetty", "Lym", "Shreya Iyer"], "Rithwik Shetty")).toBe("Rithwik Shetty"));
test("selfMatchToken", () => expect(bestSelfMatch(["Rithwik Shetty", "Lym", "Shreya Iyer"], "Rithwik")).toBe("Rithwik Shetty"));
test("selfMatchNone", () => {
  expect(bestSelfMatch(["Lym", "Shreya Iyer"], "Test User")).toBeNull();
  expect(bestSelfMatch(["Lym", "Shreya Iyer"], "")).toBeNull();
});
test("privateRelayEmailsAreHidden", () => {
  const email = "ABC123@privaterelay.appleid.com";
  expect(isApplePrivateRelayEmail(email)).toBe(true);
  expect(visibleEmail(email)).toBeNull();
  expect(fallbackDisplayName(email)).toBe("You");
});
test("regularEmailsRemainVisible", () => {
  const email = "  alex@example.com  ";
  expect(isApplePrivateRelayEmail(email)).toBe(false);
  expect(visibleEmail(email)).toBe("alex@example.com");
  expect(fallbackDisplayName(email)).toBe("Alex");
  expect(normalizedAuthEmail(null)).toBeNull();
});
test("displayNamesAreNormalized", () => {
  expect(normalizedDisplayName("  Alex Chen  ")).toBe("Alex Chen");
  expect(normalizedDisplayName("  " + "A".repeat(80) + "  ")).toHaveLength(60);
  expect(normalizedDisplayName("   ")).toBeNull();
});
test("verificationCodesAreNormalized", () => {
  expect(emailVerificationCodeLength).toBe(8);
  for (const code of ["12345678", "1234 5678", "abc12345678"]) expect(normalizedVerificationCode(code)).toBe("12345678");
  expect(normalizedVerificationCode("1234567")).toBeNull();
  expect(normalizedVerificationCode("123456789")).toBeNull();
});
const scheme = "tab",
  token = "0123456789abcdef0123456789abcdef";
test("authCallbacksRequireConfiguredLocalURL", () => {
  expect(isExpectedAuthCallbackURL("tab://auth-callback?code=abc", scheme)).toBe(true);
  expect(isExpectedAuthCallbackURL("tab://auth-callback/#access_token=abc", scheme)).toBe(true);
  for (const url of ["tab://not-auth-callback?code=abc", "https://auth-callback?code=abc", "tab://auth-callback/extra?code=abc"])
    expect(isExpectedAuthCallbackURL(url, scheme)).toBe(false);
});
test("acceptsWebLinks", () => {
  expect(inviteToken("https://tab-it.app/join/" + token, scheme)).toBe(token);
  expect(inviteToken("https://www.tab-it.app/join/" + token, scheme)).toBe(token);
});
test("acceptsCustomScheme", () => expect(inviteToken("tab://join/" + token, scheme)).toBe(token));
test("normalizesUppercaseToken", () => expect(inviteToken("https://tab-it.app/join/" + token.toUpperCase(), scheme)).toBe(token));
test("rejectsOtherLocations", () => {
  expect(inviteToken("https://example.com/join/" + token, scheme)).toBeNull();
  expect(inviteToken("https://tab-it.app/invite/" + token, scheme)).toBeNull();
});
test("rejectsMalformedTokens", () => {
  for (const t of [token.slice(0, -1), token + "0", "0123456789abcdef0123456789abcdeg"])
    expect(inviteToken("https://tab-it.app/join/" + t, scheme)).toBeNull();
});
test("rejectsAuthCallback", () => expect(inviteToken("tab://auth-callback?code=abc", scheme)).toBeNull());
test("avatar names and byte sums match the iOS helpers", () => {
  expect(avatarInitial("  alex")).toBe("A");
  expect(avatarInitial(" ")).toBe("?");
  expect(avatarInitial("👩‍💻 Alex")).toBe("👩‍💻");
  expect(avatarTone(a)).toBe("sand");
  expect(emailAvatarTone("alex@example.com")).toBe(emailAvatarTone("alex@example.com"));
});
test("a person's tone follows their account, then their email, across trips", () => {
  expect(personTone({ id: b, user_id: a, email: "alex@example.com" })).toBe(avatarTone(a));
  expect(personTone({ id: c, user_id: a, email: "other@example.com" })).toBe(avatarTone(a));
  expect(personTone({ id: b, user_id: null, email: "alex@example.com" })).toBe(emailAvatarTone("alex@example.com"));
  expect(personTone({ id: b })).toBe(avatarTone(b));
});
test("people sort self, joined, then pending names", () => {
  const p = [{ ...person(b, "Bob"), joined_at: null }, person(c, "Cara"), person(a, "Alice")];
  expect(sortedPeople(p, a).map((p) => p.id)).toEqual([a, c, b]);
});
test("import mapping produces row ledgers with no side effects", () => {
  const parsed = parseSplitwise(
    "Date,Description,Category,Cost,Currency,A,B\n2026-01-01,Taxi,Taxi,10,GBP,5,-5\n2026-01-02,Repayment,Payment,3,GBP,3,-3",
  );
  const r = mapSplitwiseRows(parsed, {
    tripID: "trip",
    userID: a,
    personIDs: { A: a, B: b },
    now,
    rowIDs: ["e", "s"],
    writeID: c,
  });
  expect(r.expenses[0]).toMatchObject({
    amount: "10",
    expense_date: "2026-01-01",
    payment_method: "card",
    category_id: D.transport.id,
  });
  expect(r.payments[0]).toMatchObject({
    trip_person_id: a,
    payment_mode: "equal",
    amount_paid: "10",
  });
  expect(r.splits.every((s) => s.split_type === "exact")).toBe(true);
  expect(r.settlements[0]).toMatchObject({
    from_person_id: a,
    to_person_id: b,
    amount: "3",
    note: null,
    settled_at: "2026-01-02T12:00:00.000Z",
  });
});
test("entity convenience derivations preserve native defaults", async () => {
  const { activePeople, hasPlaceholderEmail, isNonGroup, primaryPayerID, effectiveSplitType, effectivePaymentMethod, categoryOption } =
    await import("./presentation-helpers");
  expect(activePeople([person(a, "Alice"), { ...person(b, "Bob"), removed_at: now }]).map((p) => p.id)).toEqual([a]);
  expect(hasPlaceholderEmail({ email: a + "@users.tab" })).toBe(true);
  expect(isNonGroup({ kind: "non_group" })).toBe(true);
  expect(primaryPayerID([{ trip_person_id: b }, { trip_person_id: a }])).toBe(a);
  expect(primaryPayerID([])).toBeNull();
  expect(effectiveSplitType("legacy")).toBe("equal");
  expect(effectiveSplitType("shares")).toBe("shares");
  expect(effectivePaymentMethod("legacy")).toBe("card");
  expect(effectivePaymentMethod("bank_transfer")).toBe("bank_transfer");
  expect(categoryOption({ id: a, name: "Food", icon: "bowl-food" })).toEqual({
    id: a,
    name: "Food",
    icon: "bowl-food",
  });
});
test("import people map the self column and create normalized pending people", async () => {
  const { mapImportPeople } = await import("./splitwise-importer");
  const result = mapImportPeople({
    names: ["Alice", " Bob "],
    selfPerson: "Alice",
    tripID: "trip",
    user: { id: a, email: "  ALICE@X.TEST  ", displayName: "Alice" },
    creatorPersonID: c,
    newPersonIDs: { " Bob ": b },
    now,
    writeID: a,
  });
  expect(result.personIDs).toEqual({ Alice: c, " Bob ": b });
  expect(result.people[0]).toMatchObject({
    id: c,
    user_id: a,
    email: "alice@x.test",
    joined_at: now,
  });
  expect(result.people[1]).toMatchObject({
    id: b,
    user_id: null,
    email: b + "@users.tab",
    display_name: "Bob",
    joined_at: null,
  });
});
test("fallback names match Foundation Unicode title casing and word boundaries", () => {
  expect(fallbackDisplayName("émile@example.com")).toBe("Émile");
  expect(fallbackDisplayName("alex.chen@example.com")).toBe("Alex.Chen");
  expect(fallbackDisplayName("o'connor@example.com")).toBe("O'connor");
  expect(fallbackDisplayName("user_name@example.com")).toBe("User_Name");
  expect(fallbackDisplayName("ßeta@example.com")).toBe("Sseta");
  expect(fallbackDisplayName("neha123shetty@example.com")).toBe("Neha123Shetty");
});
