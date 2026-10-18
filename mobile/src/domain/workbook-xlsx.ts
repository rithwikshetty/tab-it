import { utf8Bytes } from "./text";
import type { Workbook } from "./trip-exporter";
import { decimalRational, roundDivide, scaledString } from "./decimal";
export function xmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
export function spreadsheetColumn(index: number): string {
  let value = index,
    result = "";
  do {
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = Math.floor(value / 26) - 1;
  } while (value >= 0);
  return result;
}
export function xmlDecimal(value: string): string {
  const r = decimalRational(value),
    rounded = scaledString(
      roundDivide(r.numerator * 10n ** 10n, r.denominator, "halfEven"),
      10,
    );
  const [whole = "0", fraction = ""] = rounded.split(".");
  return whole + "." + fraction.padEnd(2, "0");
}
export function buildWorkbookXML(workbook: Workbook): Record<string, string> {
  const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    rels = "http://schemas.openxmlformats.org/package/2006/relationships",
    office =
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
  const strings: string[] = [],
    lookup = new Map<string, number>(),
    index = (value: string) => {
      const existing = lookup.get(value);
      if (existing !== undefined) return existing;
      const n = strings.length;
      strings.push(value);
      lookup.set(value, n);
      return n;
    };
  const files: Record<string, string> = {};
  for (const [i, sheet] of workbook.sheets.entries())
    files[`xl/worksheets/sheet${i + 1}.xml`] =
      declaration +
      `\n<worksheet xmlns="${ns}">\n<sheetData>` +
      sheet.rows
        .map(
          (row, r) =>
            `<row r="${r + 1}">` +
            row
              .map((cell, c) => {
                const ref = spreadsheetColumn(c) + (r + 1);
                return cell.type === "string"
                  ? `<c r="${ref}" t="s"><v>${index(cell.value)}</v></c>`
                  : `<c r="${ref}"><v>${xmlDecimal(cell.value)}</v></c>`;
              })
              .join("") +
            "</row>",
        )
        .join("") +
      "</sheetData></worksheet>";
  files["xl/sharedStrings.xml"] =
    declaration +
    `\n<sst xmlns="${ns}" count="${strings.length}" uniqueCount="${strings.length}">` +
    strings.map((s) => "<si><t>" + xmlEscape(s) + "</t></si>").join("") +
    "</sst>";
  files["[Content_Types].xml"] =
    declaration +
    '\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n  <Default Extension="xml" ContentType="application/xml"/>\n  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\n' +
    workbook.sheets
      .map(
        (_, i) =>
          `  <Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`,
      )
      .join("\n") +
    '\n  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\n  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\n</Types>';
  files["_rels/.rels"] =
    declaration +
    `\n<Relationships xmlns="${rels}">\n  <Relationship Id="rId1" Type="${office}/officeDocument" Target="xl/workbook.xml"/>\n</Relationships>`;
  files["xl/workbook.xml"] =
    declaration +
    `\n<workbook xmlns="${ns}" xmlns:r="${office}">\n  <sheets>\n` +
    workbook.sheets
      .map(
        (s, i) =>
          `    <sheet name="${xmlEscape(s.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`,
      )
      .join("\n") +
    "\n  </sheets>\n</workbook>";
  files["xl/_rels/workbook.xml.rels"] =
    declaration +
    `\n<Relationships xmlns="${rels}">\n` +
    workbook.sheets
      .map(
        (_, i) =>
          `  <Relationship Id="rId${i + 1}" Type="${office}/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`,
      )
      .join("\n") +
    `\n  <Relationship Id="rId${workbook.sheets.length + 1}" Type="${office}/styles" Target="styles.xml"/>\n  <Relationship Id="rId${workbook.sheets.length + 2}" Type="${office}/sharedStrings" Target="sharedStrings.xml"/>\n</Relationships>`;
  files["xl/styles.xml"] =
    declaration +
    `\n<styleSheet xmlns="${ns}">\n  <fonts count="2">\n    <font><sz val="11"/><name val="Calibri"/></font>\n    <font><b/><sz val="11"/><name val="Calibri"/></font>\n  </fonts>\n  <fills count="2">\n    <fill><patternFill patternType="none"/></fill>\n    <fill><patternFill patternType="gray125"/></fill>\n  </fills>\n  <borders count="1">\n    <border><left/><right/><top/><bottom/><diagonal/></border>\n  </borders>\n  <cellStyleXfs count="1">\n    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>\n  </cellStyleXfs>\n  <cellXfs count="2">\n    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\n    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\n  </cellXfs>\n</styleSheet>`;
  return files;
}
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let i = 0; i < 8; i++)
      crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
export function workbookXLSX(workbook: Workbook): Uint8Array {
  const chunks: Uint8Array[] = [],
    central: Uint8Array[] = [];
  let offset = 0,
    centralSize = 0;
  const files = Object.entries(buildWorkbookXML(workbook)).sort(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );
  if (files.length > 65535) throw new Error("archiveTooLarge");
  for (const [path, text] of files) {
    const name = utf8Bytes(path),
      data = utf8Bytes(text),
      crc = crc32(data);
    if (name.length > 65535 || data.length > 0xffffffff || offset > 0xffffffff)
      throw new Error("archiveTooLarge");
    const local = new Uint8Array(30 + name.length),
      lv = new DataView(local.buffer);
    lv.setUint32(0, 0x04034b50, true);
    lv.setUint16(4, 20, true);
    lv.setUint16(12, 33, true);
    lv.setUint32(14, crc, true);
    lv.setUint32(18, data.length, true);
    lv.setUint32(22, data.length, true);
    lv.setUint16(26, name.length, true);
    local.set(name, 30);
    chunks.push(local, data);
    const entry = new Uint8Array(46 + name.length),
      ev = new DataView(entry.buffer);
    ev.setUint32(0, 0x02014b50, true);
    ev.setUint16(4, 20, true);
    ev.setUint16(6, 20, true);
    ev.setUint16(14, 33, true);
    ev.setUint32(16, crc, true);
    ev.setUint32(20, data.length, true);
    ev.setUint32(24, data.length, true);
    ev.setUint16(28, name.length, true);
    ev.setUint32(42, offset, true);
    entry.set(name, 46);
    central.push(entry);
    centralSize += entry.length;
    offset += local.length + data.length;
  }
  if (centralSize > 0xffffffff || offset > 0xffffffff)
    throw new Error("archiveTooLarge");
  const end = new Uint8Array(22),
    view = new DataView(end.buffer);
  view.setUint32(0, 0x06054b50, true);
  view.setUint16(8, files.length, true);
  view.setUint16(10, files.length, true);
  view.setUint32(12, centralSize, true);
  view.setUint32(16, offset, true);
  const result = new Uint8Array(offset + centralSize + end.length);
  let position = 0;
  for (const chunk of [...chunks, ...central, end]) {
    result.set(chunk, position);
    position += chunk.length;
  }
  return result;
}
