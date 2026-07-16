# How split-expense apps add and join members

Research date: 2026-07-16. Question: how do the established group-expense apps
let you add people to a group and let those people join? Covers Splitwise,
Tricount (by bunq), Settle Up, Splid, Kittysplit, and Spliit.

Sources are primary where possible: official help centers, the Settle Up public
data-model docs, the Spliit source and README, and app-store descriptions.
Claims I could only trace to reviews or third-party tutorials are marked
**unverified**.

## What is standardized

Most of these apps agree on a few things, and Splitwise is the usual outlier.

- **A group member is just a name.** Tricount, Settle Up, Splid, Kittysplit, and
  Spliit all let you add someone with a name alone. No email, no phone. The
  person becomes a placeholder in that group's ledger. Splitwise is the
  exception: its mobile apps ask for an email or phone number, and name-only
  members work only on the website.
- **People join through one secret per-group link, not per-person invites.**
  Tricount, Settle Up, Kittysplit, and Spliit each give the group a single
  shareable URL. Anyone with the link is in. Splid uses a per-group code with the
  same effect. Splitwise now has a group share link too, but historically leaned
  on email/phone invites.
- **You usually do not need an account to take part.** Splid, Kittysplit, Spliit,
  and Tricount's basics all work without registration. Splitwise requires
  accounts. Settle Up lets a member exist without an account, but seeing the
  group in the app needs one.
- **Claiming is self-selection: "which one of these is you?"** When you open a
  shared group, the app shows the list of names and asks you to pick yourself.
  Tricount, Kittysplit, Spliit, and Settle Up all work this way. There is no
  identity check behind it. Splitwise is again the exception: it matches on the
  email or account you were invited with and offers an explicit "already have an
  account, merge this in" step.
- **A placeholder who never joins just stays a placeholder.** None of the apps
  delete an unclaimed member or their balances. The ledger tracks the name, and
  the group works whether or not that person ever opens the link. Splid makes
  this a selling point: not everyone in the group has to join.
- **Abuse protection is thin and mostly undocumented.** The secret link is the
  only gate. Whoever holds it can view the whole group and claim any name.
  Settle Up is the only one with a documented off switch (the invite link can be
  deactivated). No app I read documents a defense against claiming the wrong
  person.

The interesting split is on identity. The link-first apps have no verified
identity to match against, so they let you self-select which name is you, and
they accept the risk that comes with a shared secret link. Splitwise trades that
convenience for account- and email-based matching.

## Splitwise

1. **Identifiers.** Add a group member by email address or phone number. The
   website additionally allows name-only group members; the mobile apps do not.
   A Splitwise admin confirmed this in 2016: "On our website, Splitwise does
   allow you to add group members without email addresses... My apologies that
   the same feature isn't available on our mobile apps!"
   ([add a person](https://feedback.splitwise.com/knowledgebase/articles/147041-how-do-i-add-a-new-person-to-a-group),
   [add without email/phone](https://feedback.splitwise.com/forums/162446-general/suggestions/15063162-add-friends-without-email-address-or-phone-number))
2. **Contacts integration.** The mobile apps offer inviting from device contacts.
   I did not confirm from a help-center page whether it reads the full address
   book or uses a picker. **Unverified.**
3. **Invite links.** Yes. A group's settings page (on the web) has a share link
   that lets people add themselves to the group. Recipients follow it, then click
   "Already have an account? Click here!" to attach the group instead of making a
   new account.
   ([merge an invite](https://feedback.splitwise.com/knowledgebase/articles/493592-how-can-i-merge-a-group-invite-or-friend-invite-in),
   [join an existing group](https://feedback.splitwise.com/knowledgebase/articles/239218-how-do-i-join-an-existing-group))
4. **Claiming / merging.** Matching is by the email or account you were invited
   with. The documented path is an explicit merge: follow the invite, choose
   "Already have an account? Click here!", and the group folds into your existing
   account. What happens when you sign in with a different email than the one you
   were invited with is not covered in the help center.
   ([merge an invite](https://feedback.splitwise.com/knowledgebase/articles/493592-how-can-i-merge-a-group-invite-or-friend-invite-in))
5. **Placeholder who never joins.** Not documented in the pages I read. The
   member exists as a friend/group entry regardless; Splitwise's stance is that
   "everyone involved in a bill can log on and see that bill."
   ([why add friends](https://feedback.splitwise.com/knowledgebase/articles/206028-why-do-i-have-to-add-friends-in-order-to-use-split))
6. **Abuse mitigations.** Not documented in the help pages reviewed.

## Tricount (by bunq)

1. **Identifiers.** Name only. You add participants by name during creation or by
   editing the tricount later, up to 50 people including yourself. No email or
   phone is required to add someone.
   ([managing tricounts](https://help.tricount.com/articles/how-can-i-manage-my-tricounts-and-expenses))
2. **Contacts integration.** Not documented in the help center. **Unverified.**
3. **Invite links.** A per-group share link. From the Share tab you send the link
   to others, who "tap on the link... the app handles the rest," and you can also
   have the link emailed to yourself. Whether the link expires or can be revoked
   is not documented.
   ([managing tricounts](https://help.tricount.com/articles/how-can-i-manage-my-tricounts-and-expenses),
   [FAQs](https://help.tricount.com/articles/tricount-faqs))
4. **Claiming.** Self-selection. "The app asks you to identify yourself the first
   time you become part of a tricount." You choose which participant profile is
   you, and you can change it later in settings.
   ([FAQs](https://help.tricount.com/articles/tricount-faqs))
5. **Placeholder who never joins.** Not documented; the tricount functions with
   named participants whether or not each person opens the link.
6. **Abuse mitigations.** Not documented.

Note: Tricount is owned by bunq, and the basics are usable without registration.
The "no registration for the basics" framing traces to marketing and reviews
rather than a clean help-center statement, so treat the exact account boundary as
**unverified**.

## Settle Up

Settle Up's public data-model documentation is the clearest primary source here,
because it names the entities directly.

1. **Identifiers.** A member is a "virtual entity unique per group" with a name,
   photo, and payment handles. Members are separate from users. So a group member
   is effectively name-only and does not require an account.
   ([data entities](https://api.settleup.io/entities/))
2. **Contacts integration.** Third-party guides say you can add members from
   phone contacts, but I did not confirm this from Settle Up's own docs.
   **Unverified.** ([Kopyst guide](https://www.kopyst.com/documents/how-to-create-a-new-group-and-add-new-member-to-settle-up/))
3. **Invite links.** Per-group. The group entity carries `inviteLink`
   (for example `https://join.settleup.app/abcdefgh`), an `inviteLinkHash`, and
   an `inviteLinkActive` boolean. The boolean means the link can be turned off,
   i.e. revoked.
   ([data entities](https://api.settleup.io/entities/))
4. **Claiming.** Self-selection, called "this is me" in the app. The connection
   lives at `/userGroups/<uid>/<groupId>` in a `member` field documented as
   "'This is me' in the app, connection between member and user, optional."
   A separate `permissions` record (owner / read-write / read-only) governs a
   user's access to the group, independent of which member they claim.
   ([data entities](https://api.settleup.io/entities/))
5. **Placeholder who never joins.** The member exists on its own; balances attach
   to the member entity, not to a user. A member with no linked user is a normal,
   supported state. ([data entities](https://api.settleup.io/entities/))
6. **Abuse mitigations.** The invite link can be deactivated
   (`inviteLinkActive`), and access is scoped by permission level. No wrong-person
   claim defense is documented. ([data entities](https://api.settleup.io/entities/))

## Splid

1. **Identifiers.** Name only. You add participants by typing names or, per
   reviews, pulling from contacts. No account is needed.
   ([MWM app page](https://mwm.ai/apps/splid-split-group-bills/991473495))
2. **Contacts integration.** "Either from your contacts or by typing names in
   manually" comes from a review, not a Splid primary source. **Unverified.**
   ([WhistleOut review](https://www.whistleout.com/CellPhones/Apps/splid-app-for-splitting-group-expenses))
3. **Invite / join.** A per-group mechanism: turn on the "Share Online" toggle for
   real-time sync, and others join the group, "no sign-up needed." Splid works
   offline as well, as a local group with no sharing. Reviews say the join code
   was expanded from six to nine characters; the exact length is **unverified**
   against a Splid primary source.
   ([MWM app page](https://mwm.ai/apps/splid-split-group-bills/991473495))
4. **Claiming.** Not clearly documented. On joining a shared group you presumably
   pick your name, matching the pattern of the other link-first apps, but I could
   not confirm this from a Splid primary source. **Unverified.**
5. **Placeholder who never joins.** Explicitly fine: "you don't need an account
   and not everyone from the group has to join."
   ([WhistleOut review](https://www.whistleout.com/CellPhones/Apps/splid-app-for-splitting-group-expenses),
   corroborated by the sign-up-free framing on the [MWM app page](https://mwm.ai/apps/splid-split-group-bills/991473495))
6. **Abuse mitigations.** Not documented.

## Kittysplit

1. **Identifiers.** Name only. You "enter the name of everyone who participated"
   when creating a Kitty, and manage participants later. No email or phone is
   required. ([help](https://www.kittysplit.com/en/help))
2. **Contacts integration.** None. Kittysplit is web-first and does not read a
   device address book. ([help](https://www.kittysplit.com/en/help))
3. **Invite links.** One per-group "special and secret link. People need this
   link to access the Kitty." You share it by email or chat, or through an
   "Invite to Kitty" dialog. No registration is required. Expiry and revocation
   are not documented. ([help](https://www.kittysplit.com/en/help))
4. **Claiming.** Self-identification on first access: when someone opens the link
   "they will be asked to identify themselves" and get a green checkmark showing
   they have viewed it. ([help](https://www.kittysplit.com/en/help))
5. **Placeholder who never joins.** The person stays a name in the Kitty; the
   split works without them opening the link. Not called out explicitly, but it
   follows from the model. ([help](https://www.kittysplit.com/en/help))
6. **Abuse mitigations.** The link is described as "secret," and Kittysplit
   recommends supplying your email so the link can be sent to you and is harder to
   lose. No other protection is documented; anyone with the link has access.
   ([help](https://www.kittysplit.com/en/help))

## Spliit (open source)

Spliit is a self-hostable Splitwise alternative; its source and README are the
primary source.

1. **Identifiers.** Name only. You create a group and add participants; there is
   no account system. ([site](https://spliit.app/),
   [repo](https://github.com/spliit-app/spliit))
2. **Contacts integration.** None.
3. **Sharing.** A group gets a unique, secret URL that you share. Anyone with the
   URL can open and edit the group. ([site](https://spliit.app/))
4. **Claiming.** Self-selection: "Tell the application who you are when opening a
   group." The choice is stored locally on the device rather than tied to an
   account. ([repo](https://github.com/spliit-app/spliit))
5. **Placeholder who never joins.** Participants are names in the group; the
   ledger works regardless of who opens the URL.
6. **Abuse mitigations.** None documented. The secret URL is the only gate, and
   it grants full edit access.

## Comparison

| App | Add member by | Contacts | Invite mechanism | Account needed to join | Claiming | Link revocable |
|---|---|---|---|---|---|---|
| Splitwise | Email or phone (name-only on web) | Yes, on mobile (details unverified) | Per-group share link + email/phone invites | Yes | Email/account match + explicit merge | Not documented |
| Tricount | Name | Not documented | Per-group share link | No (basics) | Self-select which participant | Not documented |
| Settle Up | Name (member is separate from user) | Claimed by third parties, unverified | Per-group `inviteLink` | For app access, yes; member can exist without | Self-select ("this is me") | Yes (`inviteLinkActive`) |
| Splid | Name (contacts, unverified) | Unverified | Per-group "Share Online" + code | No | Not documented (likely self-select) | Not documented |
| Kittysplit | Name | No | Per-group secret link | No | Self-identify on first open | Not documented |
| Spliit | Name | No | Per-group secret URL | No | Self-select on open (stored locally) | Not documented |

## Implications for tab

This is a factual comparison of tab's current model against the above, not a
recommendation.

tab adds people by **email**. `add_trip_person_by_email` creates a `trip_people`
row keyed on `(trip_id, email)`, pending until claimed. There is a unique
constraint on email per trip. Claiming is **automatic email matching**, not
self-selection: `claim_trip_people_for_current_email` runs after sign-in and sets
`user_id` on every pending row whose email equals the signed-in user's verified
auth email (`supabase/sql/15_rpc_trip_people.sql`,
`supabase/sql/03_trips_people.sql`). Auth is Apple Sign-In plus email magic link
only. There are no invite links today.

Where tab lines up with the field and where it differs:

- **Identifier.** tab requires an email to pre-add someone. That matches
  Splitwise's mobile behavior and differs from Tricount, Settle Up, Splid,
  Kittysplit, and Spliit, all of which pre-add by name alone. tab has no
  name-only placeholder.
- **Joining.** tab has no shareable per-group link, which is the one mechanism
  nearly every other app centers on. Joining tab happens by signing in with an
  email that was already pre-added.
- **Claiming.** tab matches on a verified email automatically, so it never has to
  ask "which one of these is you?" The link-first apps ask that question because
  they have no verified identity to match on. tab's approach avoids the
  wrong-person claim risk those apps carry, at the cost of the pre-adder needing
  to know each person's email in advance.
- **Placeholder who never joins.** tab keeps the row and its ledger entries, and
  a removed person keeps their history too (`supabase/sql/03_trips_people.sql`
  comments). This matches the universal behavior: an unclaimed member is a
  supported state everywhere.
- **Apple Hide My Email.** Worth flagging against finding 4. Because tab matches
  strictly on the verified auth email, a person pre-added at their real email who
  then signs in with an Apple private relay address will not auto-claim, since the
  relay address does not equal the pre-add email. The link-first apps sidestep
  this entirely by letting the user self-select their name. tab's
  `update_trip_person_email` RPC exists and is the current lever for reconciling a
  mismatched email, but that is a manual correction, not an automatic match.
