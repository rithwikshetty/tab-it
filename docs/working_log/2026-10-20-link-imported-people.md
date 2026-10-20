# Linking imported Splitwise people to friends

## Goal

Let someone who imports a Splitwise group say that an imported name is a friend who already uses tab-it, at import time or any time later, and have that friend join the trip without signing out and back in.

## Log

### 2026-10-20: findings

- The import only asked "Which one is you?". Everyone else got a placeholder email (`<id>@users.tab`). The intended way to link them was the People screen's email editor, which calls `update_trip_person_email`. The server already describes that RPC as the main path for linking imported people.
- The People screen's email editor was a `View` with `position: "absolute", bottom: 0` inside the screen's `KeyboardAvoidingView`. That view lifts content by adding bottom padding, but Yoga places absolute children against the parent's padding box, the edge outside the padding, so the padding never moved the sheet. The input's `autoFocus` raised the keyboard over the whole sheet, and only the keyboard was visible.
- The editor only took a typed email, with no way to pick a friend.
- `claim_trip_people_for_current_email` ran once, when the session opened the store. A friend who was already signed in joined only after a cold start.

### 2026-10-20: changes

- `features/people/email-sheet.tsx`: one `PersonEmailSheet`, a transparent `Modal` with its own `KeyboardAvoidingView`. It suggests `knownPeople`, ranked by `nameMatchScore` against the person's name, and refuses emails someone else in the trip already has before calling the server. The People screen and the import screen both use it.
- Domain (`splitwise-importer.ts`): `nameMatchScore` is the one name-matching rule, and `bestSelfMatch` uses it. `suggestImportLinks` prelinks a name only when exactly one known person has that exact name, and each email is used once. `mapImportPeople` takes `emails` (a `Map`, so names like "constructor" can't hit the object prototype) and uses them in place of placeholders.
- Import screen: a "Who's everyone else?" list under "Which one is you?" shows each linked email or "Not linked". `importSplitwise` passes the links through. Linked people sync through `add_trip_person_by_email` like any other added person. No server change.
- `data/sync.ts`: every full pull calls the claim first. That covers launch, foreground, reconnect and the five-minute poll, and the call left `data/session.tsx`.
- Checks: `npm run typecheck`, `npm test` (36 files, 424 tests), Prettier. Not yet run on a simulator or device.

### Open

- If a friend joins an imported trip through the invite link before anyone links their imported name, the trip has two rows for them. The sheet won't offer an email that's already in the trip. Merging the two needs a server RPC that moves payments, splits and settlements from one trip person to the other, which means a migration plan.
