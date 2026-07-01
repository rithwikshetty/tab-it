# Receipt image downsampling (memory pressure)

Goal: reduce receipt-image memory peaks after a jetsam ("terminated due to memory
issue", code 9) termination on a physical iPhone while debugging. Multi-agent
memory audit confirmed two bounded findings; the highest-value one is that
receipts were stored at full resolution and decoded at native pixel dimensions
regardless of the on-screen slot. This fix bounds both.

## 2026-06-20 — diagnosis

- Jetsam after ~12.6 min under the Xcode debugger (view/queue/XPC debugging on).
  Audit verdict: dominated by debugger overhead, no monotonic leak. But the
  receipt decode path is genuinely wasteful and worth fixing on its own merits
  (peak memory on low-RAM devices, plus a redundant ~2x decode when the 180pt
  card and the full-screen preview are both alive).
- Confirmed: `ReceiptStorage.prepareJPEG` enforced only a 9.5 MB byte cap, no
  pixel cap — a typical phone photo compresses under the cap, so the original
  resolution was stored. All three display sites used plain `AsyncImage(url:)`,
  which decodes to native pixel size (a 12 MP image → ~48 MB RGBA bitmap) no
  matter the 56pt / 180pt / full-screen slot.

## 2026-06-20 — fix

- Source cap: `ReceiptStorage.prepareJPEG` now always downscales to
  `maxStoredEdge = 2048` before the existing byte-cap loop (`downscale` is a
  no-op for already-small receipts, so no quality loss there). Bounds stored
  file size and every future decode for all new uploads at once.
- Display cap: new reusable `Components/DownsampledAsyncImage.swift` mirrors
  `AsyncImage`'s phase API but decodes via ImageIO
  `CGImageSourceCreateThumbnailAtIndex` at `maxPointSize * displayScale`. Uses
  `URLSession.shared` so encoded bytes still go through the shared `URLCache`
  like `AsyncImage`. Swapped into all 3 sites: 56pt thumbnail
  (`ExpenseEntryView`, maxPointSize 120), 180pt card (`ExpenseDetailView`,
  maxPointSize 400, full-width slot so width dominates), and full-screen
  (`ExpenseDetailView`, maxPointSize 1024). The card now decodes a tiny bitmap,
  so the card+preview redundant full-res decode is gone too.
- `sending UIImage` return types on the loader keep it clean under Swift 6
  strict concurrency (fresh value transferred to the MainActor caller).
- New file registered manually in `Tab.xcodeproj/project.pbxproj` (no
  file-system synchronized groups in this project).

## 2026-06-20 — validation

- `build_sim` (Tab scheme, iPhone 17): SUCCEEDED, 0 warnings, 0 errors.
- No unit tests cover `ReceiptStorage`; TabTests are pure-logic suites,
  untouched. Compile is the meaningful gate for this change.
