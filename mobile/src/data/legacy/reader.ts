import { LEGACY_TABLES, type LegacyRow, type LegacyRows } from "./convert";

export interface LegacyDatabase {
  getAllAsync<T>(sql: string): Promise<T[]>;
}

const DECIMALS = new Set(["ZAMOUNT", "ZAMOUNTPAID", "ZAMOUNTOWED", "ZSHAREUNITS", "ZPERCENTAGE"]);
const MONEY = new Set(["ZAMOUNT", "ZAMOUNTPAID", "ZAMOUNTOWED"]);

export function legacySelect(table: string, columns: readonly string[]): string {
  if (!(LEGACY_TABLES as readonly string[]).includes(table) || !columns.length || columns.some((c) => !/^Z[A-Z_0-9]+$/.test(c))) {
    throw new Error("Unsupported legacy table or column");
  }
  return `SELECT ${columns.map((c) => {
    if (MONEY.has(c)) return `CASE WHEN typeof("${c}") = 'real' THEN printf('%!.26g', "${c}") ELSE CAST("${c}" AS TEXT) END AS "${c}"`;
    return DECIMALS.has(c) ? `CAST("${c}" AS TEXT) AS "${c}"` : `"${c}"`;
  }).join(", ")} FROM "${table}"`;
}

export async function readLegacyRows(db: LegacyDatabase): Promise<LegacyRows> {
  const rows = {} as LegacyRows;
  for (const table of LEGACY_TABLES) {
    const columns = await db.getAllAsync<{ name: string }>(`PRAGMA table_info("${table}")`);
    rows[table] = await db.getAllAsync<LegacyRow>(legacySelect(table, columns.map((c) => c.name)));
  }
  return rows;
}
