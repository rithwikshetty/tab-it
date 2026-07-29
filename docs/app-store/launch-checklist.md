# tab-it 1.3.0 (16) App Store checklist

State of the App Store release as of 18 July 2026. Update this file as items complete.

## Done (engineering — nothing left here)

- [x] In-app account deletion (guideline 5.1.1(v)), edge function + DB purge, pgTAP tests
- [x] Contact picker in the add-person flow
- [x] Landing page live at https://tab-it.app, mobile-verified, privacy at /privacy
- [x] Custom SMTP via Resend, sender auth@tab-it.app
- [x] Branded sign-in emails, code-only (no clickable link, so corporate mail
      scanners can't auto-create accounts)
- [x] Email rate limit 20/hour
- [x] Cloudflare Turnstile CAPTCHA on email sign-in, enforced server-side,
      verified end to end on a real device
- [x] Cross-provider sign-in linking (Google + Apple, same email, one account)
- [x] User-facing rename to tab-it (display name lives in project.yml)
- [x] App Store icon alpha channel stripped (was causing the placeholder grid
      icon in App Store Connect)
- [x] Debug fixture people restricted to mock auth (were breaking real-auth sync)
- [x] Listing copy written: `docs/app-store/metadata.md`
- [x] App Privacy answers written: `docs/legal/app-store-privacy-labels.md`

## Remaining (Rithwik, in App Store Connect and on device)

- [ ] Archive and upload version 1.3.0 (16) from Product → Archive.
- [ ] App Store (Distribution) tab → 1.3.0 listing: paste every field from
      `docs/app-store/metadata.md` (name, subtitle, promo text, description,
      keywords, URLs, categories, copyright, age rating)
- [ ] App Privacy section: answer from `docs/legal/app-store-privacy-labels.md`,
      privacy policy URL https://tab-it.app/privacy
- [ ] Upload 6.9" screenshots from docs/app-store/screenshots/ (generated at
      1320×2868 on an iPhone 16 Pro Max class simulator)
- [ ] Real-device account-deletion test (Settings → Delete account, then sign
      back in)
- [ ] Select build 16 on the 1.3.0 page and Submit for Review
- [ ] Hygiene, non-blocking: delete the temporary full-access Resend API key
      (keep the sending-access one — Supabase SMTP uses it)

## After submission

- Review typically takes 1–2 days for a first app; expect at least one round of
  questions. The review notes suggestion in metadata.md explains the
  no-password sign-in.
- [x] Production-safe database conventions are active: no reset/recreate
      command, applied migrations are immutable, and future changes require
      forward-only compatibility-preserving migrations.
