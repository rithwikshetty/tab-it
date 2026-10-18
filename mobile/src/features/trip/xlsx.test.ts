import { strFromU8, unzipSync } from "fflate";
import { describe, expect, it } from "vitest";

import { workbookToXlsx } from "./xlsx";

describe("workbookToXlsx", () => {
  it("writes one worksheet per sheet with numeric and text cells", () => {
    const bytes = workbookToXlsx({
      sheets: [
        { name: "Summary", rows: [[{ type: "string", value: "Total & co" }, { type: "number", value: "12.5" }]] },
        { name: "Summary", rows: [] },
      ],
    });
    const files = unzipSync(bytes);
    expect(Object.keys(files)).toContain("xl/worksheets/sheet2.xml");
    const sheet = strFromU8(files["xl/worksheets/sheet1.xml"]!);
    expect(sheet).toContain('<c r="B1"><v>12.5</v></c>');
    expect(sheet).toContain("Total &amp; co");
    expect(strFromU8(files["xl/workbook.xml"]!)).toContain('name="Summary 2"');
  });
});
