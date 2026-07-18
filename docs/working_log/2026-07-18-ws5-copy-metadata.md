# WS5 copy and metadata fixes

## Goal

Fix delete-dialog copy, distinguish the missing verified email invite error, update App Store metadata for version 1.3.0 (16), and disclose Cloudflare Turnstile in the privacy policy. Keep the changes scoped to issues #27, #31, #30, and #29, with focused tests and the requested full validation.

## 2026-07-18 19:10:29 BST

Read the repository guidance, domain context, and plain-writing guide before changing user-facing text. The initial source scan found recovery promises only in the three reported delete dialogs. Other matches for "restore" were developer comments, not user-visible copy. RootView currently groups Postgres error `22023` with invalid or disabled invite errors, so it needs a separate mapping.

## 2026-07-18 19:10:58 BST

Removed the unsupported 30-day recovery promise from the trip, expense, and settlement delete dialogs. Kept each dialog's first sentence unchanged because it is truthful and reads clearly on its own.

## 2026-07-18 19:11:28 BST

Tried to commit fix A as `fix: remove unsupported delete recovery copy Refs #27`. The sandbox denied creation of the Git worktree's `index.lock` because the repository metadata is outside the writable workspace. Continued with the scoped implementation and will retry after validation.

## 2026-07-18 19:12:03 BST

Added a focused Swift Testing case for the `22023` invite error before implementation. Generated the ignored Xcode project from `project.yml`, but the red test could not reach compilation because the sandbox blocks CoreSimulator and Xcode's default DerivedData and package-cache writes. Added a pure error-message helper and routed Postgres invite errors through it. Error `22023` now explains that the account has no verified email and tells the user to verify it before reopening the link. Existing `P0002` and `42501` copy and token handling remain unchanged; unknown Postgres errors still use the offline fallback.

## 2026-07-18 19:12:43 BST

Reviewed the recent 1.3.0 feature commits and updated the App Store What's New copy with invite links, offline use and sync, offline receipt viewing, expense-row lent or borrowed amounts, simpler currency display and settle-up suggestions, and notification reliability. Updated the launch checklist to version 1.3.0 (16), replaced stale 1.0 listing and build references, and removed the completed invite-link item from the old post-launch backlog.

## 2026-07-18 19:13:12 BST

Read the full privacy policy before editing it. Added the email sign-in check to the collected-data list and named Cloudflare Turnstile in the provider section, including the IP address and browser characteristics it receives and that the check blocks bots. Updated the policy's effective date to 18 July 2026. Listing the data in both places keeps the policy's statement that no unlisted data is collected consistent.

## 2026-07-18 19:17:00 BST

Validation: TabCore passed all 154 tests after redirecting its module cache and disabling SwiftPM's nested sandbox. The full TabTests command against iPhone 17 could not run because this sandbox cannot connect to CoreSimulatorService; `simctl` could not access any simulator device set. A generic Xcode build was also blocked while SwiftPM tried to start its nested `sandbox-exec`. As a focused fallback, extracted the invite error mapper into its own source file and ran its actual two Swift Testing cases through a temporary package; both passed. The same source and test files also type-checked for the iOS simulator target. The privacy page passed a stack-based tag-balance check and `xmllint --html --noout`. Final copy scans found no remaining user-visible recovery promise in the app and no stale 1.0 listing or page reference in the App Store docs.

## 2026-07-18 19:17:31 BST

Retried the first logical commit after validation. Git was still unable to create the external worktree `index.lock`, so this environment cannot stage or commit the finished changes. The working tree remains scoped but uncommitted.

## 2026-07-18 19:21:02 BST

Fixed the invite-join compile error by allowing the error-message mapper to accept the optional Postgres error code supplied by `PostgrestError`. A missing code now returns no mapped message, preserving the intended fallback to RootView's offline message; unrelated codes continue to do the same. Added focused tests for both nil and unrelated codes without changing the existing `22023`, `P0002`, or `42501` messages.

## 2026-07-18 19:22:17 BST

Focused validation compiled the updated mapper with Swift 6 and exercised nil, unrelated, `22023`, `P0002`, and `42501` inputs successfully. The iOS test runner remains unavailable in this sandbox because CoreSimulatorService cannot be reached; direct type-checking of the Swift Testing file is also unavailable outside Xcode because this command-line toolchain does not expose the `Testing` module.
