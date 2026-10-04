# Handoff

Updated 2026-10-04, after v1 was built on `dev`. The maintainer had the UI designed in Claude Design
(`design/prototype/`), picked its final "v1", and asked for it one to one. It's built, tested
against a mock of Úschovna and in three real uploads, and pushed. Nothing is released yet: `main`
is still the initial commit.

**The brief.** A macOS menu-bar app that makes sending a file through
[uschovna.cz](https://www.uschovna.cz) take seconds instead of a browser round trip: drag files,
drop them on the zone under the menu-bar icon (or use Finder's Quick Actions › Send with
Úschovna), and the share link is on the clipboard. The sender email is set once. Úschovna is for
files too big for Discord or email. Minimal, frictionless and fast, in the spirit of the
maintainer's other menu-bar app, betterTab (`../betterTab`), whose conventions this repo follows.
What v1 does is `docs/spec.md`; how it's built is `docs/architecture.md`.

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

- **`origin`** is the public repository
  [Luksanss/quickUschovna](https://github.com/Luksanss/quickUschovna).
- **`main`** has only `00f03d1` (Initial commit). No release has run.
- **`dev`** has v1 and is pushed: the Xcode project (app + `QuickAction` extension), the model,
  the surfaces, the UI, the Úschovna client and its mock tests, the Quick Action, the app icon, the
  release workflow and scripts, and the docs.
- **The agents' worktrees are gone,** and their builds are unregistered from Launch Services. Four
  agents built the client, the UI, the Quick Action and the release pipeline in parallel worktrees;
  their commits were cherry-picked onto `dev`.
- **On the maintainer's Mac:** a Debug build from `build/DerivedData.noindex` may still be running
  (started by the agent). Its real settings now hold the maintainer's sender address and one test
  link in Recent ("quickUschovna test 3.zip", from an approved test; it expires on 2026-10-18). The
  Quick Action that's registered is the one in `build/DerivedData.noindex`'s Release build.

## Next action

1. **The maintainer tries it by hand** (what the agent couldn't do without a mouse; see Known gaps):
   - drag a file from Finder onto the drop zone, and onto the icon; a folder from Downloads (no
     permission prompt expected);
   - turn on the Quick Action (Finder › right-click › Quick Actions › Customize… › Send with
     Úschovna), then send two files and a folder with it;
   - click just around the panel and on the icon while the panel is open (the shadow must let
     clicks through); Esc in the panel; hover in the bubble and the Recent rows;
   - dark mode; Launch at Login once it's installed from a release.
2. **Before the first merge to `main`:** create the `release` environment and its two secrets
   (`docs/releasing.md` § Signing with your certificate). Without them the workflow refuses to release, and if the job
   runs first, GitHub creates the environment without the main-only rule.
3. **Release 1:** when the maintainer says v1 works, the agent opens the `dev` → `main` pull request;
   the maintainer merges it with a merge commit, which publishes `v1.0.<commit count>`. Then check
   the run, install the disk image, and repeat the Quick Action test from the installed app.

## Decisions already settled

- **v1 is Claude Design's final design, built one to one** (the maintainer, 2026-10-04): the drop
  zone under the icon, the icon taking drops too, and Finder's Quick Action; the bubble; the panel
  (not an `NSMenu`); English UI. Where the app differs from the prototype, `docs/spec.md` says so.
- **A native client of Úschovna's website upload** (the maintainer), not the real page in a hidden
  `WKWebView`: faster and smaller. It sits behind `UploadService`, so an official-API backend can
  replace it if Úschovna breaks or says no (Findings: Fallbacks).
- **The app's output is one public link to share** (the maintainer): no recipients, no message.
- **Folders are zipped by our own writer, stored, not compressed** (`Zipper.swift`): media doesn't
  shrink, and storing runs at disk speed. Apple's `zip` and `ditto` were rejected (Findings).
- **No in-app updater.** The design has no Check for Updates…, so releases are a disk image on
  GitHub without Sparkle; users update by hand (`docs/releasing.md`).
- **Release builds are re-signed without `get-task-allow`**, which Xcode puts in every build
  (`scripts/build-release.sh`). betterTab had shipped with it; its fix is on betterTab's `dev`.
- **Formats follow the system's locale**, as the spec says: on a Czech Mac it's "3,1 MB" and
  "Expires 18. 10." next to English text.
- **A folder dragged before it's dropped shows its name without a size** (spec § Ways in), to avoid
  a permission prompt mid-drag.
- **The repository is public from day one.** Nothing secret in it; release secrets live only in the
  `release` environment, which only `main` can use. The Team ID in `project.pbxproj` is fine.
- **Branches: `dev` and `main` only;** no CI, only CD; the agent may push `dev` and open the
  `dev` → `main` pull request, never merge it or push `main`. betterTab's PRs merge with a merge
  commit; keep that.

## Findings worth keeping

**Úschovna, from reading its site (2026-10-04) and three real uploads the maintainer approved:**
- **There's no API.** The website uploads through its own AJAX protocol, now written up in
  `docs/uschovna-protocol.md`. No captcha, no email verification, recipients optional.
- **The server answers `"status": true`** where the page checks `1 == status`. JavaScript's loose
  equality makes that pass, so the client compares the same way (`UschovnaWire`). The first real
  attempt stopped right there, before any package existed.
- **The finish answer's code is `<public>/<secret>`.**
  - `https://www.uschovna.cz/zasilka/<public>/` is the recipients' page: download, "zbývá 30
    stažení", no delete. That's the link the app shares, with its trailing slash.
  - `…/zasilka/<public>/<secret>` is the sender's page with "SMAZAT ZÁSILKU". Never share it or
    log it.
  - With the slash encoded as `%2F` the page is a 404.
- **The recipients' page shows the sender's address** ("<sender> vám posílá zásilku"). The README
  says so.
- **Packages went to `www306`/`www307.uschovna.cz`.** Names with Czech diacritics arrived intact,
  and so did a zipped folder: the page listed it at 996.7 kB, exactly our archive's size.
- **The terms** (from 2014, TISCALI MEDIA, a.s.) don't mention automation or other clients. They
  describe uploading "přes webové rozhraní" and allow changing the service without notice. Reading:
  not forbidden, grey, fine for personal low-volume use, can break any day.
- **Limits:** free is 30 GB (the script's own limit is 30 GiB; the app uses 30 × 10⁹ bytes, which is
  stricter), 14 days, 30 downloads per link, 1000 files per package. Premium is 40 Kč per package
  (unlimited downloads); Úschovna+ is 79 Kč / 3 months.
- **Fallbacks with an official API,** should it come to that: Smash, Filemail, a self-hosted Send,
  or Cloudflare R2 presigned links. WeTransfer's API was retired in 2022.

**macOS:**
- **Apple's `/usr/bin/zip` can't flag names as UTF-8** (no `-UN`), so Czech names arrive garbled on
  Windows. **`ditto -k --zlibCompressionLevel 0` still deflates,** and over 4 GB it writes archives
  that `zipinfo` reports as damaged. zlib's `crc32` is hardware-accelerated (~25 GB/s), so our own
  writer runs at disk speed.
- **Protected folders.**
  - Listing a folder in Desktop, Documents or Downloads before the drop would raise the permission
    prompt mid-drag; a file's size (metadata) doesn't.
  - Items that arrive by a drop or by Launch Services (the Quick Action) can be read without a
    prompt, for as long as the app runs.
- **A third-party Quick Action arrives switched off.** The user ticks it once under Quick Actions ›
  Customize…; the setting is keyed by the extension's bundle ID, so it survives rebuilds.
- **Every worktree build registers its own copy of the extension under the same ID,** and PlugInKit
  may pick a stale one. `lsregister -u` a worktree's builds before deleting it, and check
  `pluginkit -mAvvv -i com.luksanss.quickUschovna.QuickAction`.
- **What the agent can and can't do here.** It can capture the screen (`screencapture`), but it
  can't post mouse or key events (no Accessibility, and it mustn't grant itself any). That's why
  `DebugControl` exists.
- **Live tests run on the maintainer's screen while they work.** Their clicks elsewhere dismiss
  bubbles (`clickedOutside`), which looks like a bug in a scripted run but isn't. Crop captures to
  the surfaces.
- **macOS 27's system blue is `#007AFF` in both appearances**; the prototype's dark swatch is
  `#0A84FF`. The app uses the system accent.

## Known gaps

- **Not verified by mouse:**
  - real drags from Finder onto the zone and the icon (the window-delegate dragging path);
  - the Quick Action clicked in Finder (verified up to AppKit's own call);
  - the shadow letting clicks through, and Esc;
  - Launch at Login from an installed build.
  All of this is in Next action 1.
- **The release workflow has never run,** and nothing is notarized, so the first launch needs Open
  Anyway.
- **Open protocol questions** (`docs/uschovna-protocol.md`, last section): how the server treats
  a chunk sent again after a lost answer (above all a file's last chunk), and whether `still_alive`
  matters.
- **Rare failures get the generic message.** Over 1000 items in one drop, or nothing but empty
  files, ends in "Úschovna isn’t answering" rather than a message of its own; the design has none.
- **Focusing the panel's Sender field selects the whole address,** as macOS does; the prototype
  leaves the text unselected.
- **There's no unit-test target.** The model is exercised through `--simulate` and `DebugControl`,
  the client through its mock.

## Safety constraints

- **`main` is the release branch.** Every push to `main` publishes a GitHub Release. Never commit to
  `main`, never push it, never merge into it on your own judgement.
- **A real upload is a real send** from the maintainer's address through someone else's service,
  and triggers a control email. The maintainer approved up to five small test uploads on
  2026-10-04; three were used. Ask again before any further real upload.
- **Be a polite client.** No bulk sending, no parallel hammering, no load tests against Úschovna.
- **The sender email lives in the app's settings on the Mac, never in the repo.**
- **Never log, store or share the part of a finish code after its slash.**
