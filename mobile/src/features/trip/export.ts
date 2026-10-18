import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";

import { buildWorkbook, extractExportData, workbookXLSX, type TripRows } from "@/domain";
import { localOffset } from "@/lib/dates";

/** Writes the trip as an .xlsx workbook and opens the share sheet. */
export async function shareTripExport(rows: TripRows, tripName: string) {
  const safe =
    tripName
      .replace(/[/:]/g, "-")
      .replace(/[\\*?"<>|]/g, "")
      .trim()
      .slice(0, 60) || "Trip";
  const file = new File(Paths.cache, `${safe} Expenses.xlsx`);
  if (file.exists) file.delete();
  file.create();
  await file.write(workbookXLSX(buildWorkbook(extractExportData(rows, undefined, localOffset))));
  if (!(await Sharing.isAvailableAsync())) throw new Error("Sharing isn't available on this device.");
  await Sharing.shareAsync(file.uri, {
    mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    UTI: "org.openxmlformats.spreadsheetml.sheet",
    dialogTitle: `${tripName} expenses`,
  });
}
