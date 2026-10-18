import { normalizedCode } from "./currency-catalog";
import { abs, addDecimals, allocateMinor, decimalRational, normalizeDecimal, scaledString } from "./decimal";
import { fromMinor, toMinor } from "./money";
export interface ImportShare {
  person: string;
  amount: bigint;
}
export interface ImportExpense {
  type: "expense";
  date: string;
  description: string;
  category: string;
  currency: string;
  total: bigint;
  payments: ImportShare[];
  splits: ImportShare[];
}
export interface ImportSettlement {
  type: "settlement";
  date: string;
  description: string;
  currency: string;
  amount: bigint;
  from: string;
  to: string;
}
export type ImportRow = ImportExpense | ImportSettlement;
export interface ImportWarning {
  line: number;
  message: string;
}
export interface ImportResult {
  people: string[];
  rows: ImportRow[];
  expenses: ImportExpense[];
  settlements: ImportSettlement[];
  warnings: ImportWarning[];
}
export class ImportParseError extends Error {
  constructor(
    public readonly code: "empty" | "missingHeader" | "unexpectedHeader" | "noPeople",
    public readonly found?: string[],
  ) {
    super(code);
    this.name = "ImportParseError";
  }
}
export function parseCSVFields(line: string): string[] {
  const fields: string[] = [];
  let current = "",
    inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i]!;
    if (inQuotes) {
      if (char === '"') {
        if (line[i + 1] === '"') {
          current += '"';
          i++;
        } else inQuotes = false;
      } else current += char;
    } else if (char === '"') inQuotes = true;
    else if (char === ",") {
      fields.push(current);
      current = "";
    } else current += char;
  }
  fields.push(current);
  return fields;
}
export function splitCSVRecords(text: string): {
  line: number;
  fields: string[];
}[] {
  return text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .flatMap((line, i) => (line ? [{ line: i + 1, fields: parseCSVFields(line) }] : []));
}
export function parseImportDecimal(text: string): string | null {
  const value = text.trim();
  return /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value) ? normalizeDecimal(value) : null;
}
export function parseImportDate(text: string): string | null {
  const parts = text.trim().split("-").filter(Boolean);
  if (parts.length !== 3 || parts.some((p) => !/^\+?\d+$/.test(p))) return null;
  const [year, month, day] = parts.map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year!, month! - 1, day!);
  date.setUTCHours(12, 0, 0, 0);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
export function reconstructImport(
  total: bigint,
  currency: string,
  nets: readonly {
    person: string;
    net: bigint;
  }[],
  people: readonly string[],
  line: number,
  warnings: ImportWarning[],
): {
  payments: ImportShare[];
  splits: ImportShare[];
} | null {
  const debtors = nets.filter((n) => n.net < 0n),
    payers = nets.filter((n) => n.net > 0n);
  const warn = (message: string) => warnings.push({ line, message });
  if (!payers.length) {
    if (!debtors.length) {
      const solo = people[0];
      if (!solo) return null;
      warn(`Row has no balances; recorded as paid in full by ${solo}.`);
      return {
        payments: [{ person: solo, amount: total }],
        splits: [{ person: solo, amount: total }],
      };
    }
    warn("Row doesn't balance (no payer); skipped.");
    return null;
  }
  const payersOwed = total + debtors.reduce((n, d) => n + d.net, 0n);
  if (payersOwed < 0n) {
    warn("Row doesn't balance (debts exceed the amount); skipped.");
    return null;
  }
  const sorted = [...payers].sort((a, b) => (a.person < b.person ? -1 : a.person > b.person ? 1 : 0));
  const shares = allocateMinor(
    payersOwed,
    sorted.map((p) => p.person),
    Object.fromEntries(sorted.map((p) => [p.person, p.net.toString()])),
  );
  const splits = debtors.map((d) => ({ person: d.person, amount: -d.net }));
  const payments: ImportShare[] = [];
  for (const p of sorted) {
    const owed = shares[p.person]!;
    if (owed > 0n) splits.push({ person: p.person, amount: owed });
    payments.push({ person: p.person, amount: p.net + owed });
  }
  const drift = total - payments.reduce((n, p) => n + p.amount, 0n);
  if (drift !== 0n) {
    const largest = payments.reduce((best, p) => (p.amount > best.amount ? p : best));
    largest.amount += drift;
    if (abs(drift) > 2n) warn(`Row's amounts didn't sum cleanly; adjusted by ${fromMinor(drift, currency)} to balance.`);
  }
  if (
    payments.reduce((n, p) => n + p.amount, 0n) !== total ||
    splits.reduce((n, p) => n + p.amount, 0n) !== total ||
    [...payments, ...splits].some((p) => p.amount < 0n)
  ) {
    warn("Row's amounts don't balance; skipped.");
    return null;
  }
  return {
    payments: payments.filter((p) => p.amount > 0n),
    splits: splits.filter((p) => p.amount > 0n),
  };
}
export function parseSplitwise(text: string): ImportResult {
  const records = splitCSVRecords(text.replace(/^\uFEFF/, "")),
    header = records[0];
  if (!header) throw new ImportParseError("empty");
  const expected = ["Date", "Description", "Category", "Cost", "Currency"],
    leading = header.fields.slice(0, 5).map((s) => s.trim());
  if (leading.length !== 5) throw new ImportParseError("missingHeader");
  if (leading.some((v, i) => v.toLowerCase() !== expected[i]!.toLowerCase())) throw new ImportParseError("unexpectedHeader", leading);
  const columnNames = header.fields
      .slice(5)
      .map((s) => s.trim())
      .filter(Boolean),
    people = [...new Set(columnNames)];
  if (!people.length) throw new ImportParseError("noPeople");
  const warnings: ImportWarning[] = [],
    rows: ImportRow[] = [];
  if (people.length !== columnNames.length)
    warnings.push({
      line: header.line,
      message: "Duplicate person names in the header are merged into one person.",
    });
  for (const record of records.slice(1)) {
    const field = (i: number) => record.fields[i]?.trim() ?? "",
      warn = (message: string) => warnings.push({ line: record.line, message });
    if (record.fields.every((f) => !f.trim())) continue;
    const description = field(1),
      category = field(2),
      currency = normalizedCode(field(4));
    if (description.toLowerCase() === "total balance") continue;
    const date = parseImportDate(field(0));
    if (!date) {
      warn(`Unreadable date "${field(0)}"; row skipped.`);
      continue;
    }
    const cost = parseImportDecimal(field(3));
    if (cost === null || decimalRational(cost).numerator <= 0n) {
      warn("Unreadable or zero amount; row skipped.");
      continue;
    }
    const netValues = new Map<string, string[]>();
    let invalid = false;
    for (const [i, name] of columnNames.entries()) {
      const raw = field(5 + i);
      if (!raw) continue;
      const value = parseImportDecimal(raw);
      if (value === null) {
        warn(`Unreadable amount "${raw}"; row skipped.`);
        invalid = true;
        break;
      }
      netValues.set(name, [...(netValues.get(name) ?? []), value]);
    }
    if (invalid) continue;
    const netDecimals = people
      .map((person) => ({
        person,
        net: addDecimals(netValues.get(person) ?? []),
      }))
      .filter((n) => n.net !== "0");
    const total = toMinor(cost, currency);
    if (category.toLowerCase() === "payment" || description.toLowerCase() === "settle all balances") {
      const positive = netDecimals.filter((n) => decimalRational(n.net).numerator > 0n),
        negative = netDecimals.filter((n) => decimalRational(n.net).numerator < 0n);
      if (positive.length === 1 && negative.length === 1) {
        rows.push({
          type: "settlement",
          date,
          description,
          currency,
          amount: total,
          from: positive[0]!.person,
          to: negative[0]!.person,
        });
        continue;
      }
      warn(`Payment row "${description}" wasn't a two-person transfer; imported as an expense.`);
    }
    const reconstructed = reconstructImport(
      total,
      currency,
      netDecimals.map((n) => ({
        person: n.person,
        net: toMinor(n.net, currency),
      })),
      people,
      record.line,
      warnings,
    );
    if (reconstructed)
      rows.push({
        type: "expense",
        date,
        description,
        category,
        currency,
        total,
        ...reconstructed,
      });
  }
  return {
    people,
    rows,
    warnings,
    expenses: rows.filter((r): r is ImportExpense => r.type === "expense"),
    settlements: rows.filter((r): r is ImportSettlement => r.type === "settlement"),
  };
}
export const SplitwiseImport = {
  parse: parseSplitwise,
  parseFields: parseCSVFields,
  splitRecords: splitCSVRecords,
  parseDecimal: parseImportDecimal,
  parseDate: parseImportDate,
  reconstruct: reconstructImport,
};
