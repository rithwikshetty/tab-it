import type { TripSpendSummary } from "./trip-analytics";
import { spendFromRows } from "./trip-analytics";
import type { LedgerRows } from "./models";
import { roundDivide, scaledString } from "./decimal";
import { formatMoney } from "./money-formatter";
function ratio(part: bigint, whole: bigint): number {
  return whole > 0n ? Number(scaledString(roundDivide(part * 10n ** 40n, whole), 40)) : 0;
}
export function resolveOverview(
  summaries: readonly TripSpendSummary[],
  currentPersonID: string,
  personName: (id: string) => string,
  categoryName: (id: string | null) => string,
  locale = "en-US",
) {
  const pages = summaries.map((summary) => {
    const yours = summary.perPerson.find((p) => p.personID === currentPersonID),
      max = summary.perCategory.reduce((n, c) => (c.total > n ? c.total : n), 0n),
      fmt = (n: bigint) => formatMoney(n, summary.currency, locale);
    return {
      id: summary.currency,
      currency: summary.currency,
      totalSpent: fmt(summary.total),
      youPaid: fmt(yours?.paid ?? 0n),
      yourShare: fmt(yours?.share ?? 0n),
      yourSharePercent: summary.total > 0n ? `${roundDivide((yours?.share ?? 0n) * 100n, summary.total)}% of trip spend` : null,
      people: summary.perPerson.map((p) => ({
        id: p.personID,
        name: p.personID === currentPersonID ? "You" : personName(p.personID),
        isYou: p.personID === currentPersonID,
        paid: fmt(p.paid),
        share: fmt(p.share),
        shareFraction: ratio(p.share, summary.total),
      })),
      categories: summary.perCategory.map((c) => ({
        id: c.categoryID ?? "uncategorized",
        categoryID: c.categoryID,
        name: categoryName(c.categoryID),
        amount: fmt(c.total),
        percent: ratio(c.total, summary.total),
        fraction: ratio(c.total, max),
      })),
    };
  });
  return {
    currencies: pages.map((p) => p.currency),
    pages,
    isEmpty: !pages.length,
  };
}
export function overview(
  rows: LedgerRows,
  currentPersonID: string,
  personName: (id: string) => string,
  categoryName: (id: string | null) => string,
  locale = "en-US",
) {
  return resolveOverview(spendFromRows(rows), currentPersonID, personName, categoryName, locale);
}
export const OverviewPresenter = { resolve: resolveOverview, overview };
