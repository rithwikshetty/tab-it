# Domain port

Import production types and functions from `@/domain`. Implementations and tests live in this folder.

## Money and row boundaries

Row types in `records.ts` retain Supabase field names and decimal strings. Domain ledger values use integer `bigint` minor units. For example, USD `"12.5"` becomes `1250n`; JPY `"1250"` becomes `1250n`; KWD `"1.250"` becomes `1250n`.

`fromMinor` and `normalizedAmount` remove insignificant trailing zeros, matching `SyncService.decimalString` and `NSDecimalNumber.stringValue`. They return `"12.5"`, `"0"`, and `"1.25"`. `plainAmountString` renders fixed entry precision, such as `"12.50"`.

`toMinor` and `normalizedAmount` round pulled over-precision values half away from zero. Calculators reject over-precision inputs rather than normalizing them. Display and currency-switch rounding use half even, matching `NumberFormatter`; raw negative display values retain their minus sign when rounded to zero. Share labels use half away from zero, matching `NSDecimalRound(.plain)`. Equal and weighted splits floor minor units, including negative totals. Weighted allocation compares exact rational remainders.

`LedgerRows` contains separate `expenses`, `payments`, `splits`, and `settlements` arrays. `TripRows` adds `trip`, `people`, and optional `categories`. Row-based presenters accept these plain rows. Callers select the relevant trip's rows. `ledgerFromRows` converts them to the nested arithmetic ledger without changing the input. Pass `normalizedAmount` as the data layer's `normalizeAmount` callback when merging pulls.

Money arithmetic never converts to `number`. Chart ratios convert to `number` only after exact bigint division; timestamps, array indices, UUID bytes, and archive sizes also use numbers.

## Public modules

The implementation uses plain objects and functions; the two error types extend `Error`.

| Module | Public functions | Behavior |
| --- | --- | --- |
| `records.ts` | Types only | Supabase row contracts, decimal strings, UUIDs, dates, sync fields, and enums. |
| `models.ts` | `toLedgerExpense`, `toLedgerSettlement`, `ledgerFromRows`, `paymentMethodDisplayName` | Adapt row ledgers to bigint values and expose native payment labels; exports `PaymentMode`, payment/split/ledger types, `LedgerRows`, `TripRows`, and `splitTypes`. |
| `money.ts` | `toMinor`, `fromMinor`, `sanitizeAmountInput`, `decimalFromInput`, `parseAmountInput`, `sanitizeShareInput`, `shareString` | Exact money conversion, native entry sanitation, decimal-prefix parsing, and share labels. |
| `decimal.ts` | `decimalRational`, `abs`, `compare`, `floorDivide`, `roundDivide`, `scaledString`, `normalizeDecimal`, `addDecimals`, `subtractDecimals`, `allocateMinor` | Bigint decimal/rational primitives, explicit rounding, and largest-remainder allocation. |
| `currency-catalog.ts` | `normalizedCode`, `isSupportedCurrency`, `currencyMetadata`, `displayMetadata`, `fractionDigits`, `minorUnitMultiplier`, `hasValidPrecision`, `normalizedAmount`, `searchCurrencies` | Currency lookup, fallback metadata, precision rules, pull normalization, and search. |
| `money-formatter.ts` | `plainAmountString`, `convertAmountText`, `formatMoney` | Exact fixed en-US entry/display strings, symbol-only output, and code fallback; `formatMoney` also accepts `Money`. |
| `split-calculator.ts` | `calculateSplits`, `equalPercentages` | Equal, exact, shares, and percentage splits; deterministic remainders and validation through `CalculationError.code` and `.details`. |
| `payment-calculator.ts` | `calculatePayments` | Equal/exact payer allocation with payer-specific error names. |
| `balance-engine.ts` | `canonicalPair`, `distributePairs`, `computeBalances`, `balancesFromRows` | Net payment/split ledgers, quantize proportional pair debts, apply settlements, and emit ordered mirrored balances. |
| `debt-simplifier.ts` | `simplifyDebts`, `mirroredSimplifiedBalances` | Derive deterministic trip-wide repayments without changing ledger history. |
| `conflict-resolver.ts` | `timestampUnits` | Turn ISO timestamps, including Postgres microseconds and UTC offsets, into comparable bigint nanoseconds. |
| `trip-state-deriver.ts` | `deriveTripState` | Derive active/completed state from outstanding balances and an injected clock/threshold. |
| `overall-balance-aggregator.ts` | `resolveIdentity`, `identityKey`, `aggregateBalances`, `balanceBreakdown` | Resolve user/email identities and net mirrored balances across containers. |
| `trip-analytics.ts` | `summarizeSpend`, `spendFromRows` | Per-currency expense totals, paid/share ledgers, and deterministically sorted category totals; excludes settlements and deleted expenses. |
| `view-state.ts` | Types only | Balance summaries, debt suggestions, expense/settlement rows, and timeline states. |
| `balance-presenter.ts` | `balanceSummaries`, `simplifiedGroups`, `suggestedPayment` | Format simplified balances and choose the current person's outgoing repayment before incoming repayments. |
| `trip-presenter.ts` | `tripCard` | Derive members, active/completed state, and empty/owed/owing/mixed/settled card text. |
| `timeline-presenter.ts` | `expenseRow`, `settlementRow`, `timelineDays` | Format ledger rows and date groups, ordered by creation time, with expense-only daily currency totals. |
| `overview-presenter.ts` | `resolveOverview`, `overview` | Format trip spend pages, current-person summaries, exact percentage labels, and chart ratios. |
| `friends-presenter.ts` | `friendTone`, `friendsList`, `friendDetail` | Derive active/settled friends, gross banners, per-source repayment targets, and shared history after trip-wide debt simplification. |
| `activity-presenter.ts` | `isActivityUnread`, `unreadActivityCount`, `activityRow`, `activitySections`, `activityNavigation` | Map every activity action, unread/read/mute/join/dismiss rules, date sections, and openable-detail navigation fallback. |
| `expense-dates.ts` | `calendarOffset`, `offsetMinutes`, `calendarDay`, `localInstant`, `formatCalendarDate`, `displayExpenseDate`, `formatClockTime`, `dayID`, `dayLabel` | Format English dates/times and preserve stored calendar days using UTC or explicit offset arithmetic; settlements remain instants. |
| `currency-defaults.ts` | `validCurrency`, `initialCurrency`, `mostRecentTripCurrency`, `defaultCurrency` | Choose trip currency, saved selection, supplied device-region currency, then INR. |
| `presentation-helpers.ts` | `avatarTone`, `emailAvatarTone`, `personTone`, `nameCharacters`, `avatarInitial`, `compareNames`, `sortedPeople`, `normalizedEmail`, `isValidEmail`, `inviteJoinErrorMessage`, `hasPlaceholderEmail` | Native avatar identity, people ordering, permissive email rules, invite errors, default categories, and placeholder-email detection. |
| `auth-helpers.ts` | `inviteToken` | Read the invite token from a tab-it.app join link or a join link on the app's own scheme. |
| `splitwise-import.ts` | `parseCSVFields`, `splitCSVRecords`, `parseImportDecimal`, `parseImportDate`, `reconstructImport`, `parseSplitwise` | CSV/header parsing, source-line warnings, exact expense reconstruction, and settlement direction; `ImportParseError` preserves header failure kinds. |
| `splitwise-importer.ts` | `splitwiseCategoryID`, `nameMatchScore`, `bestSelfMatch`, `suggestImportLinks`, `mapSplitwiseRows`, `mapImportPeople` | Map categories, score display-name matches, pick the self name, suggest friends' emails for exact name matches, build pending people (linked emails or placeholders), and map imported rows using caller-supplied IDs and timestamps. |
| `payment-split-draft.ts` | `createPaymentSplitDraft`, `selectedSplitType`, `enteredDraftTotal`, `seedPaymentSplitDraft`, `setPayerMode`, `togglePayer`, `setDraftText`, `setSplitMode`, `toggleParticipant`, `computedDraftPayments`, `computedDraftSplits` | Immutable payer/split form state, one-time seeds, mode changes, typed fields, and validated ledger results. |
| `trip-exporter.ts` | `extractExportData`, `buildWorkbook` | Preserve native export extraction, five-sheet order, headers, details, and summaries. |
| `workbook-xlsx.ts` | `xmlEscape`, `spreadsheetColumn`, `xmlDecimal`, `buildWorkbookXML`, `workbookXLSX` | Pure native-format spreadsheet XML and deterministic stored-ZIP XLSX bytes, with exact decimal cell text. |
| `text.ts` | `utf8Bytes` | Encode Unicode as UTF-8 without browser text-encoder globals. |
| `index.ts` | Re-exports | Single production entry point; fixture data and test helpers remain test-only. |

## Integration details

- Calculator input amounts and weights are decimal strings. Calculator results, balances, analytics totals, import shares, and repayment suggestions are bigint minor units. Convert with `fromMinor` before writing row amounts.
- Display output is fixed English with en-US grouping `,` and decimal `.`. Locale arguments remain accepted for caller compatibility and do not change output. Currency names and the supported set are a checked-in English snapshot generated directly from Swift `CurrencyCatalog`; symbols are globally distinct under NFKC folding. Saved-currency persistence and device-region currency lookup stay with the caller.
- Date functions default to UTC. `TimeZoneOffset` accepts minutes east of UTC, `UTC`/`GMT`/`Z`, an explicit string such as `UTC+05:30` or `-07:00`, or a date-specific offset resolver. `CalendarOptions.utcOffsetMinutes` takes a number or resolver, with `timeZone` retained as an explicit-offset alias. IANA names require resolution by the caller; these modules do not contain a timezone database. To follow the device zone across DST, pass `instant => -instant.getTimezoneOffset()` at the UI boundary.
- The domain uses no `Intl` API, locale collation, or browser text-encoder global. Money is formatted from bigint digits. Date labels use English month/weekday tables and shifted UTC getters. Name initials/truncation use code-point arrays with combining-mark, emoji-modifier, flag-pair, and ZWJ grouping; sorting uses deterministic case-insensitive English accent ordering.
- Activity read/dismiss metadata lives outside the server row. Supply `ActivityOptions.localState` keyed by activity ID. Supply joined timestamps, mute IDs, current user, and current trip-person IDs explicitly.
- Draft transitions return a new state; store their return value.
- Import creation, UUID generation, authentication, RPCs, persistence, rollback, file writing, sharing, and UI work remain outside these modules. The mapping functions require IDs and timestamps from the caller.
- XLSX output is a `Uint8Array`; the caller writes/shares it.

## Swift and Kotlin findings

- Kotlin uses `BigInteger` for Splitwise reconstruction. The TypeScript version also avoids the Swift importer's fixed-width minor-unit integer limit.
- Swift floors negative equal/weighted allocations. Kotlin's division and `RoundingMode.DOWN` truncate toward zero; negative equal remainders can also fail `take`. The port preserves Swift flooring and tests it.
- Swift's calendar parser rolls invalid dates into the next month and accepts non-padded components. Kotlin's `LocalDate.parse` rejects them. The port preserves Swift's calendar behavior and tests rollover.
- Swift's common currency set and locale symbols differ from the JDK's broader available-currency catalog. The port uses the Swift snapshot, including JPY zero digits and KWD/BHD three digits.
- Swift decimal division has finite precision and Kotlin proportional division rounds to 24 fractional digits. TypeScript keeps exact rational fractions, as required, before allocating integer minor units.
- Clock, timezone offsets, saved preferences, and activity-local metadata are explicit inputs. Display language and money separators are fixed English/en-US for Hermes compatibility. Activity day labels use the supplied clock consistently; Swift's `isDateInToday`/`isDateInYesterday` consult the system clock even when its presenter receives `now`.

## Source coverage and limits

The tests port the TabCore `@Test` declarations for the behaviour these modules keep, including the parameterized unsupported-mode cases and `contracts/domain/parity-v1.json` read from the repository at test time. The real Splitwise CSV fixture is copied unchanged from its Swift test. Additional cases cover inferred rounding/serialization rules, microsecond timestamps, negative splits, large amounts/weights, prototype-named import people, date rollover, chart ratios, and exact XLSX output.

SwiftData persistence/merge lifecycle, local-store wiping, DTO decoding machinery, async paging, serial gates, and sync-generation/cursor storage tests belong to the data/service layer. Their database, network, or mutable service implementations were not moved into the pure domain. The money-normalization values from the SwiftData merge test also have a pure row-adapter test here.

A regression test removes `Intl` and `TextEncoder` before importing the public entry point, then exercises money, trip cards, activity, timelines, friends, names, currency search, and XLSX generation.
