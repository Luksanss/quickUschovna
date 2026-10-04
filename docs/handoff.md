# Handoff

Written 2026-10-04, when the handoff system was set up and the repository published. There's no
prior session to carry forward, so this first version records the brief, the state at setup, the
conventions agreed then, and the research into whether Úschovna can be used at all. Everything
below is meant to be rewritten by `/handoff-update` as work lands. Treat the structure as a
starting point, not a form to fill in.

**The brief.** A macOS menu-bar app that makes sending a file through
[uschovna.cz](https://www.uschovna.cz) take seconds instead of a browser round trip. Today it's:
open Chrome, load Úschovna, type the sender email, add files, click send, wait for the link. The
target is: drag files onto the menu-bar icon, and the share link is on the clipboard. The sender
email is set once in the app's settings, so nothing is typed per send. Úschovna is for files too
big for Discord or email. The goal is minimal, frictionless and fast, in the spirit of the
maintainer's other menu-bar app, betterTab (`../betterTab`), whose conventions this repo follows.
The UI is designed in Claude Design first; the agent then implements it.

**Convention.** The current handoff lives at this path and is rewritten in place by every
`/handoff-update`. It's archived only **at a release**, when `dev` is merged into `main` because
the maintainer says a version works. At that point it's copied to
`docs/archive/handoffs/<ISO date>.md` in the same commit, with a topical suffix such as `-ci` (not
a number) if that date is taken. If the merge goes through a GitHub pull request, the archive
can't be in the merge commit, so the next `/handoff-update` on `dev` writes it. This file is then
started fresh. Never leave the live handoff under `docs/archive/handoffs/`; readers are told to
treat that directory as historical only.

This document records what is **not** obvious from the code or `git log`: decisions and the
reasoning behind them, findings that were expensive to learn, and the next action. There's no
ticket tracker; the next action below is the backlog.

## Working copy state

- **`origin` is the public repository
  [Luksanss/quickUschovna](https://github.com/Luksanss/quickUschovna),** created on 2026-10-04.
  Anyone can read it.
- **`main`** has only `00f03d1` (Initial commit, `.gitattributes`), pushed so the repository has
  its default branch.
- **`dev`** carries the setup: `.gitignore`, `README.md`, and the handoff system (this file,
  `docs/archive/handoffs/README.md`, `.claude/skills/handoff*/`, `CLAUDE.md`). Pushed.
- **No code, no Xcode project, no build.** Nothing runs locally.

## Next action

In this order; each step gates the next.

1. **Optionally, ask Úschovna** (info@uschovna.cz) whether a personal client is fine or whether
   there's an API. The maintainer sends it; an agent may draft it.
2. **Pick the client approach** (Findings): a native client of the website's AJAX upload
   (fast, small, grey) or the real page driven in a hidden `WKWebView` (more defensible, heavier,
   breaks when their page changes). Either way, behind a small provider interface so an
   official-API backend can replace Úschovna if it breaks or says no. The agent recommended the
   native client on 2026-10-04; not yet decided.
3. **Design in Claude Design.** The menu-bar drop target and its states (idle, drag-over,
   uploading with progress, done with the link copied, error), and the one-time settings (sender
   email). As minimal as betterTab.
4. **Implement on `dev`**: a plain Xcode menu-bar project like betterTab's, with the build as the
   first required check (Known gaps). The first real send needs the maintainer's go-ahead
   (Safety).
5. **Release pipeline**: CD modelled on betterTab's `.github/workflows/release.yml` and
   `docs/releasing.md` (a push to `main` builds, signs and publishes a GitHub Release, with
   Sparkle for updates). The maintainer creates the `release` environment (Selected branches:
   `main` only) and sets its secrets; agents never handle keys. What carries over from betterTab:
   - **The Apple Development certificate is reused,** not regenerated. It's the maintainer's
     developer identity (Personal Team, expires 2027-09-29), not a per-app key. The same `.p12`
     goes into this repo's `release` environment as `SIGNING_CERT_P12` and
     `SIGNING_CERT_PASSWORD`; environment secrets don't cross repositories.
   - **Sparkle's EdDSA key is new, one per app.** Reusing betterTab's would work, but a leak of one
     key would then let someone sign updates for both apps, and a second key costs nothing. Trap:
     `generate_keys` without `--account` finds betterTab's key already in the login keychain and
     just prints it, so it silently reuses it. Use a separate account name (e.g.
     `--account quickUschovna`, checked against `generate_keys --help` of the Sparkle version in
     use) for `generate_keys`, its `-x` export and `sign_update`.

## Decisions already settled

- **The app's output is one link to share** (the maintainer, 2026-10-04): the package link
  Úschovna gives the sender, put on the clipboard. No recipients and no message, so Úschovna
  emails nobody but the sender's own control email. Sharing that link is how the maintainer
  already uses Úschovna, e.g. for files too big for Discord.
- **The repository is public from day one** (the maintainer, at setup). Everything committed is
  world-readable: no keys, tokens, certificates, personal addresses or Team IDs in the repo.
  Secrets live only in the GitHub `release` environment, which only `main` can use.
- **Branches: `dev` and `main`, nothing else.** Work is committed straight to `dev`; `main` moves
  only by merging `dev` when the maintainer says a version works. No feature branches: one
  developer, one user. Same as betterTab.
- **No CI, only CD.** Checks run locally before a commit; the only workflow will be the release on
  push to `main`. The maintainer's call at setup.
- **The agent may push `dev` and open the `dev` → `main` pull request,** but never merges it and
  never pushes `main` (CLAUDE.md). betterTab's PRs are merged with a merge commit (`Merge pull
  request #7 from Luksanss/dev`); keep that, because squashing a long-lived `dev` into `main` makes
  the two diverge at every release.
- **The README says only what the research supports:** unofficial, no API, uses the same upload
  as the website, can break without notice, personal low-volume use. Keep it that way as the
  client approach is decided.

## Findings worth keeping

From research on 2026-10-04: public pages and the site's JavaScript only, nothing sent. The
terms, `robots.txt`, the endpoint names and the price list were checked twice.

- **Úschovna has no API.** Nothing for developers, businesses or partners on any tier;
  `https://www.uschovna.cz/api/` answers 403. The website uploads through its own AJAX protocol,
  in `https://www.uschovna.cz/www/js/uschovna.js` (`?v1.1.85` at the time):
  1. `POST /ajax/package_target/` with file names and sizes → the upload host. (`/ajax/test_xss`
     decides whether that host is used cross-origin or the page's own.)
  2. `POST {host}/ajax/zalozeni_zasilky` with `sender_mail`, `package_recipients[]`, `message`,
     `premium_checkbox`, `mail_subject`, `language_to` → a package code.
  3. `POST {host}/ajax/ajax_upload/{timestamp}`: the file as raw chunks of 100 KB to 10 MB
     (adaptive), described by the headers `X_PACKAGE`, `X_NAME`, `X_SIZE`, `X_USIZE` (offset),
     `X_CSIZE`, `X_TMP`. The answer `res=1` means continue, `res=2` means the file is done.
  4. `/ajax/still_alive` during long uploads; then `zalozeni_zasilky` again with
     `package_code` and `dokoncit: true` to finish the package.
  5. The browser goes to `/zasilka/{code}`.
  An older multipart form (`/uploaded/{id}/`, field `f[]`) is still in the page. The only cookie
  is `PHPSESSID`. There's no captcha: no reCAPTCHA, hCaptcha or Turnstile in the page or the JS.
- **No email verification in the client.** `/ajax/emailcheck` only checks that the address's
  domain has a mail server. Whether the server checks more is unknown. **Recipients are
  optional:** the JS asks for a sender address only when recipients are given, and the
  maintainer confirmed it from use on 2026-10-04.
- **The sender's free link can be shared anywhere, but its downloads are capped** (the
  maintainer, from use, 2026-10-04). So the price list's "link to share anywhere" Premium
  feature is really about the unlimited downloads. The cap is presumably the free tier's 30 per
  link, not counted exactly. The app can mention it but doesn't need to work around it.
- **The terms don't mention automation at all.** `https://www.uschovna.cz/vseobecne_podminky_uschovna`,
  effective 2014-11-01, operator TISCALI MEDIA, a.s.: nothing on bots, scripts, scraping,
  reverse engineering or third-party clients. Two clauses matter: unregistered users may use
  "Nahrávání Zásilek přes webové rozhraní Serveru", i.e. uploading through the web interface; and
  the operator may change the service at any time without notice. The free tier is paid for by
  ads (`/ajax/reklama`, video ads during the upload), which a native client doesn't show. Reading:
  not forbidden, grey (it isn't the web interface and it skips the ads), fine for personal
  low-volume use, and it can break any day. `robots.txt` only keeps crawlers off `/zasilka/`. The
  privacy policy lists the sender's address among data used for marketing, and the sender gets a
  control email for each package.
- **Limits** (`https://www.uschovna.cz/cenik`): free is 30 GB, kept 14 days, and each recipient
  gets their own link for 30 downloads; the sender gets a link too. The Premium package (40 Kč
  online) is 50 GB, 90 days, unlimited downloads, and is the tier advertised as giving a link to
  share wherever you like. Úschovna+ (79 Kč / 3 months, 259 Kč / year) is packages up to 50 GB
  for 90 days, 50 GB of permanent storage, no ads, history. No tier includes an API. The JS caps
  a package at 50 GB.
- **Prior art, all unofficial:** `tomas-binek/uschovna-bash-api` and
  `tomas-binek/uschovna-uploader` (2018, the old multipart form, printing `/zasilka/` links as
  share links, and a folder-watching uploader that is close to this app);
  `Bendzamen/davinci-resolve-autoupload` (2024, Selenium filling in the form, dismissing the
  cookie dialog). The flow has been scriptable for years.
- **Fallbacks with an official API,** if Úschovna says no or breaks: Smash (API and SDKs, paid
  from €10/month), Filemail (API on paid plans, 20 requests per 10 s), self-hosted Send with the
  `ffsend` client, Cloudflare R2 presigned URLs (free tier, links valid up to 7 days).
  WeTransfer's public API was retired on 2022-05-31. Dropshare is an existing paid menu-bar app
  that does drop-to-link for S3, R2 and others.

## Known gaps

- **No required check.** There's no build system yet. When the Xcode project lands, its clean
  build (Debug and Release) becomes the required check: write the exact `xcodebuild` command into
  `CLAUDE.md` and `.claude/skills/handoff-update/SKILL.md` in that same commit, and add
  `Bash(xcodebuild *)` to that skill's `allowed-tools`.
- **No CD and no `release` environment yet** (Next action 5).
- **No licence.** betterTab has none either; it's the maintainer's call for a public repo.

## Safety constraints

- **`main` is the release branch.** Once CD exists, every push to `main` publishes a GitHub
  Release that installs on the maintainer's Mac. Never commit to `main`, never push it, never
  merge into it on your own judgement.
- **A real upload is a real send.** It goes out from the maintainer's email address through
  someone else's service, and triggers a control email. Agents don't trigger real Úschovna
  uploads, not even with a test file, unless the maintainer asks for that one upload.
- **Be a polite client.** No bulk sending, no parallel hammering, no load tests against
  Úschovna. One person's sends, the way the website would make them.
- **The sender email lives in the app's settings on the Mac, never in the repo.** The repo is
  public.
