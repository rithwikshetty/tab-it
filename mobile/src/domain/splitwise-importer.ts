import { DefaultCategories } from "./presentation-helpers";
import type { ImportResult } from "./splitwise-import";
import type { Expense, ExpensePayment, ExpenseSplit, Settlement } from "./records";
import { fromMinor } from "./money";
import { normalizedEmail } from "./presentation-helpers";
export function splitwiseCategoryID(category: string): string {
  const key = category.toLowerCase().trim();
  if (["food and drink", "dining out", "dining", "groceries", "liquor", "restaurant", "drinks"].includes(key))
    return DefaultCategories.food.id;
  if (
    [
      "transportation",
      "taxi",
      "car",
      "gas/fuel",
      "fuel",
      "gas",
      "bus/train",
      "bus",
      "train",
      "plane",
      "parking",
      "bicycle",
      "transport",
    ].includes(key)
  )
    return DefaultCategories.transport.id;
  if (["hotel", "rent", "mortgage", "accommodation", "lodging", "hostel", "airbnb"].includes(key)) return DefaultCategories.lodging.id;
  if (["entertainment", "games", "movies", "music", "sports", "activities"].includes(key)) return DefaultCategories.activities.id;
  if (["shopping", "clothing", "electronics", "furniture", "household supplies", "gifts"].includes(key))
    return DefaultCategories.shopping.id;
  return DefaultCategories.other.id;
}
/** Score given to two display names that match exactly, ignoring case and outer spaces. */
export const EXACT_NAME_MATCH = Number.MAX_SAFE_INTEGER;
/** How closely two display names match: `EXACT_NAME_MATCH`, else the number of words they share, ignoring case. */
export function nameMatchScore(a: string, b: string): number {
  const x = a.toLowerCase().trim(),
    y = b.toLowerCase().trim();
  if (!x || !y) return 0;
  if (x === y) return EXACT_NAME_MATCH;
  const words = new Set(y.split(" ").filter(Boolean));
  return [...new Set(x.split(" ").filter(Boolean))].filter((t) => words.has(t)).length;
}
export function bestSelfMatch(people: readonly string[], displayName: string): string | null {
  let best: string | null = null,
    score = 0;
  for (const person of people) {
    const s = nameMatchScore(person, displayName);
    if (s > score) {
      best = person;
      score = s;
    }
  }
  return best;
}
/**
 * Emails to link imported names to before import: a name is linked only when
 * exactly one known person has that exact name, and each email is used once.
 */
export function suggestImportLinks(
  names: readonly string[],
  known: readonly { email: string; displayName: string }[],
): Map<string, string> {
  const links = new Map<string, string>();
  const used = new Set<string>();
  for (const name of names) {
    const exact = known.filter((k) => nameMatchScore(k.displayName, name) === EXACT_NAME_MATCH);
    const email = exact.length === 1 ? normalizedEmail(exact[0]!.email) : null;
    if (email && !used.has(email)) {
      links.set(name, email);
      used.add(email);
    }
  }
  return links;
}
export function mapSplitwiseRows(
  parsed: ImportResult,
  options: {
    tripID: string;
    userID: string;
    personIDs: Readonly<Record<string, string>>;
    now: string;
    rowIDs: readonly string[];
    writeID: string;
  },
): {
  expenses: Expense[];
  payments: ExpensePayment[];
  splits: ExpenseSplit[];
  settlements: Settlement[];
} {
  const expenses: Expense[] = [],
    payments: ExpensePayment[] = [],
    splits: ExpenseSplit[] = [],
    settlements: Settlement[] = [];
  const sync = {
    updated_at: options.now,
    created_at: options.now,
    write_id: options.writeID,
  };
  for (const [index, row] of parsed.rows.entries()) {
    const id = options.rowIDs[index];
    if (!id) throw new Error("Missing import row ID");
    const personID = (name: string) => {
      const pid = options.personIDs[name];
      if (!pid) throw new Error(`Missing person mapping: ${name}`);
      return pid;
    };
    if (row.type === "expense") {
      expenses.push({
        ...sync,
        id,
        trip_id: options.tripID,
        amount: fromMinor(row.total, row.currency),
        currency: row.currency,
        category_id: splitwiseCategoryID(row.category),
        description: row.description,
        expense_date: row.date.slice(0, 10),
        receipt_storage_path: null,
        payment_method: "card",
        created_by: options.userID,
        last_edited_by: null,
        deleted_at: null,
      });
      const single = row.payments.length === 1 && row.payments[0]!.amount === row.total;
      for (const p of row.payments)
        payments.push({
          ...sync,
          expense_id: id,
          trip_person_id: personID(p.person),
          amount_paid: fromMinor(p.amount, row.currency),
          payment_mode: single ? "equal" : "exact",
        });
      for (const s of row.splits)
        splits.push({
          ...sync,
          expense_id: id,
          trip_person_id: personID(s.person),
          amount_owed: fromMinor(s.amount, row.currency),
          split_type: "exact",
          share_units: null,
          percentage: null,
        });
    } else
      settlements.push({
        ...sync,
        id,
        trip_id: options.tripID,
        from_person_id: personID(row.from),
        to_person_id: personID(row.to),
        amount: fromMinor(row.amount, row.currency),
        currency: row.currency,
        note: null,
        settled_at: row.date,
        created_by: options.userID,
        deleted_at: null,
      });
  }
  return {
    expenses,
    payments,
    splits,
    settlements,
  };
}
export const SplitwiseImporter = {
  categoryID: splitwiseCategoryID,
  bestSelfMatch,
  suggestLinks: suggestImportLinks,
  mapRows: mapSplitwiseRows,
  mapPeople: mapImportPeople,
};
export function mapImportPeople(options: {
  names: readonly string[];
  selfPerson: string | null;
  /** Real emails for imported names, so those people can claim their spot; the rest get placeholders. */
  emails?: ReadonlyMap<string, string>;
  tripID: string;
  user: { id: string; email: string | null; displayName: string };
  creatorPersonID: string;
  newPersonIDs: Readonly<Record<string, string>>;
  now: string;
  writeID: string;
}): {
  people: import("./records").TripPerson[];
  personIDs: Record<string, string>;
} {
  const sync = {
    created_at: options.now,
    updated_at: options.now,
    write_id: options.writeID,
  };
  const creator: import("./records").TripPerson = {
    ...sync,
    id: options.creatorPersonID,
    trip_id: options.tripID,
    user_id: options.user.id,
    email: options.user.email !== null ? options.user.email.trim().toLowerCase() : options.user.id.toLowerCase() + "@users.tab",
    display_name: options.user.displayName,
    invited_by: options.user.id,
    joined_at: options.now,
    removed_at: null,
  };
  const people = [creator],
    personIDs: Record<string, string> = Object.create(null) as Record<string, string>;
  if (options.selfPerson !== null) personIDs[options.selfPerson] = creator.id;
  for (const name of options.names) {
    if (personIDs[name] !== undefined) continue;
    const id = options.newPersonIDs[name];
    if (!id) throw new Error(`Missing person ID: ${name}`);
    personIDs[name] = id;
    const email = options.emails?.get(name);
    people.push({
      ...sync,
      id,
      trip_id: options.tripID,
      user_id: null,
      email: email ? normalizedEmail(email) : id.toLowerCase() + "@users.tab",
      display_name: name.trim(),
      invited_by: options.user.id,
      joined_at: null,
      removed_at: null,
    });
  }
  return { people, personIDs };
}
