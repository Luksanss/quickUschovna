# Handoff

Written 2026-10-04, between releases. Release 2 is on `main` and published as **v1.0.47**. `dev`
carries what comes next: Check for Updates… in the panel, through Sparkle, and a README trimmed to
what a user needs. The maintainer hasn't tried it yet, and the updater can only be tried end to
end across two releases that both have it (Next action). The handoff written while the drop zone
was worked out is archived at `docs/archive/handoffs/2026-10-04-drop-zone.md`; release 1's, with
how v1 was built and tested, at `docs/archive/handoffs/2026-10-04.md`. This file is archived at
the next release.

**The brief.** A macOS menu-bar app that makes sending a file through
[uschovna.cz](https://www.uschovna.cz) take seconds instead of a browser round trip: drag files
towards the menu-bar icon and drop them on the zone that opens under it as the drag gets close (or
use Finder's Quick Actions › Send with Úschovna), and the share link is on the clipboard. The
sender email is set once. What the app does is `docs/spec.md`; how it's built is
`docs/architecture.md`; the design it implements one to one, with the differences listed in the
spec, is `design/prototype/quickUschovna v1.dc.html`.

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

- **`main`** is release 2: v1.0.47, published 2026-10-04 with its disk image and its one note,
  "Open the drop zone as a file drag comes near the menu-bar icon". Local `main` matches
  `origin/main`.
- **`dev`** is `main` plus the updater (`feat: check for updates from the panel`), the README
  trim and this handoff, pushed to `origin/dev`. No pull request is open.
- **The Sparkle key is set up.** The private key is in the login keychain under the account
  `quickUschovna` and in the `release` environment as `SPARKLE_ED_PRIVATE_KEY` (both 2026-10-04);
  the public half is `SUPublicEDKey` in `quickUschovna/Info.plist`. A copy belongs in the
  maintainer's password manager (`docs/releasing.md` § Updates).
- **On the maintainer's Mac:** v1.0.43 is installed in `/Applications` and running; v1.0.47 isn't
  installed. The Debug build with `--simulate` that the drop zone was tried with no longer runs.
- **Two copies of the Quick Action are registered** with PlugInKit: the installed one (1.0.43) and
  the one in `build/DerivedData.noindex`'s Release build (1.0), which every run of the required
  checks registers again. PlugInKit elects the installed one (`pluginkit -mvvv -i
  com.luksanss.quickUschovna.QuickAction`, without `-A`, checked after a rebuild on 2026-10-04).
  If Finder ever launches a DerivedData build instead, `lsregister -u` that build.

## Next action

1. **Release 3, when the maintainer says so:** the agent opens the `dev` → `main` pull request,
   the maintainer merges it. The run now also signs the disk image and publishes `appcast.xml`
   beside it; it fails if the secret doesn't match `SUPublicEDKey`. Check that the release has
   both files.
2. **Install release 3 by hand** over v1.0.43 (Open Anyway again). It's the first version with the
   updater, so it can't arrive through it. Check that Finder's Send with Úschovna opens the
   installed app, Launch at Login (never tried from an installed build), and that Check for
   Updates… says "You're up to date!".
3. **The first in-app update is release 4.** On release 3, Check for Updates… should offer it,
   install it and relaunch. Watch for: Open Anyway asked again or not (Sparkle lifts the
   quarantine; untried on macOS 27); the sender, Recent, Launch at Login and the Quick Action
   surviving.
4. **The backlog** (Known gaps), in no fixed order; the maintainer picks.

## Decisions already settled

- **v1 is Claude Design's final design, built one to one**; differences are listed in
  `docs/spec.md`. A native client of Úschovna's website upload, behind `UploadService`. One public
  link per drop. Folders zipped by our own stored writer. Release builds re-signed without
  `get-task-allow`. Formats follow the system locale. The reasons are in
  `docs/archive/handoffs/2026-10-04.md`.
- **Check for Updates…, as betterTab has it** (the maintainer, 2026-10-04, after v1.0.47). This
  reverses v1's "no in-app updater". Sparkle 2.10.0 checks only when the row is chosen; the
  details are `docs/spec.md` § Updates and `docs/architecture.md` § Updates. Settled with it:
  - **Sparkle comes from this repository's own package,** tools included
    (`build/DerivedData.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/` after any build).
    The maintainer didn't want the setup to depend on betterTab's checkout.
  - **quickUschovna has its own Sparkle key,** not betterTab's. Sparkle allows one key for every
    app; separate keys mean a leak or a loss affects one app only. The maintainer chose that.
  - **Install and Relaunch waits while anything is queued** (`Updater`, Sparkle's
    postpone-relaunch delegate method), because quitting would cut off an upload. A failed
    package counts too, until it's retried or cancelled.
  - **Debug builds show the row, but it only beeps** (the agent's call). betterTab hides it in
    Debug; here the panel is reviewed in Debug builds and the design gallery, so it looks the
    same, and a dev build still never replaces itself with a release.
  - **Only the row, no version line** like betterTab's menu has (the agent's call): Sparkle's
    windows show the version, and the panel stays minimal.
- **The README is short:** install, use, updating, and the warning that the app is unofficial and
  can break any day (the maintainer, 2026-10-04: too long). Úschovna's price table went; it links
  to their price list instead.
- **The drop zone opens when a file drag comes near the icon, not when it starts** (the
  maintainer, 2026-10-04, after using v1.0.43). The prototype opens it for any file drag, which on
  a real desktop got in the way. Opening only on the icon itself was tried and dropped: reaching
  the menu bar runs the drag into the top of the screen, and macOS opens Mission Control. The
  maintainer picked "near the icon" over "icon only, with the macOS setting switched off" (which
  helps only their Mac) and "back to any drag". "Near" is within 80 pt of the zone's place
  (`SurfaceMetrics.dropZoneApproach`), kept as first built. Once open, the zone stays until the
  drag ends. `DragMonitor` still follows every file drag and measures its files, so the label and
  size are ready when the zone appears.
- **The repository is public.** Nothing secret in it; release secrets live only in the `release`
  environment, which only `main` can use. The Team ID in `project.pbxproj` and `SUPublicEDKey`
  are fine.
- **Branches: `dev` and `main` only;** no CI, only CD; the agent may push `dev` and open the
  `dev` → `main` pull request, never merge it or push `main`. Merge with a merge commit. Commits
  that never shipped can be folded before they're pushed, because `feat`/`fix`/`perf` subjects
  become the release notes.

## Findings worth keeping

- **Úschovna's protocol and what the real server does** are in `docs/uschovna-protocol.md`. The
  three that matter most:
  - it answers `"status": true` where the page checks `1 == status`;
  - the finish code is `<public>/<secret>`, and only `https://www.uschovna.cz/zasilka/<public>/`
    may be shared, because the secret opens the sender's page with "SMAZAT ZÁSILKU";
  - the recipients' page shows the sender's address.
- **The macOS findings** (zip tools, protected folders, the Quick Action arriving switched off,
  worktree builds registering copies of the extension, what the agent can capture but not click)
  are in `docs/archive/handoffs/2026-10-04.md`, § Findings.
- **A file drag that touches the top of the screen opens Mission Control** with macOS's default
  settings (Desktop & Dock's "Drag windows to top of screen to enter Mission Control" is unset in
  `com.apple.dock`, so on). Seen in the maintainer's recording of 2026-10-04, about 0.1 s after the
  pointer reached the top edge. An app can't stop it, only keep the drop below the menu bar.
- **A real drag can only be tried by hand.** The agent can't post mouse events, so the path a real
  drag takes (`DragMonitor`'s global monitors and the pointer's position, then `FileDrop` on the
  status item's or the zone's window) is tried by the maintainer; they did on 2026-10-04.
  `DebugControl` plays the model's side: `drag <path>`, `icon`, `unicon`, `over`, `out`,
  `enddrag`, with `dump <file>` showing the zone's window.
- **The client's checks are 25 scenarios** (`scripts/uschovna/Main.swift`, one
  `scenarios.append` each). Release 1's pull request said 26; that was a miscount.
- **Sparkle's `generate_keys` without `--account` never makes a new key** when the keychain
  already has one under its default account: it prints that one, which on this Mac is
  betterTab's. Signing locally needs `sign_update --account quickUschovna` for the same reason;
  `scripts/make-appcast.sh` passes it.
- **The appcast step can be tried without either real key:** add a throwaway Ed25519 public key
  to the built app's `Info.plist` under `build/release-DerivedData.noindex`, then pipe the
  matching private key into `scripts/make-appcast.sh`. Done on 2026-10-04; a mismatched key fails
  in `scripts/check-update-signature.swift`, as it should.
- **Release notes built on `dev` list every commit since the start:** the `v*` tags sit on
  `main`'s merge commits, which aren't ancestors of `dev`. On the release runner, `HEAD` is `main`
  and the notes start at the last tag.
- **`observe` inside an `NSObject` subclass means KVO's,** not the app's `observe`
  (`Surfaces/Observe.swift`); `Updater` calls `quickUschovna.observe`.
- **The agent's tooling refused `generate_keys -p`** (reading the public key) as access to a
  secret store, so the maintainer ran it. Expect the same for anything touching the Sparkle key.

## Known gaps

- **Nothing is notarized,** so first launch needs Open Anyway.
- **The updater hasn't run end to end** (Next action 2–3). Install and Relaunch during a send can
  only be tried in a Release build, with a real upload, so ask first.
- **Open protocol questions** (`docs/uschovna-protocol.md`, last section): a chunk sent again after
  a lost answer, above all a file's last chunk; whether `still_alive` matters.
- **Rare failures get the generic message:** over 1000 items in one drop, or only empty files, ends
  in "Úschovna isn’t answering".
- **A drag `DragMonitor` didn't notice opens no zone.** The icon still takes the drop. It notices a
  drag by the drag pasteboard's change count since mouse-down; no such miss has been seen.
- **Focusing the panel's Sender field selects the whole address,** as macOS does; the prototype
  leaves it unselected.
- **No unit-test target.** The model is exercised through `--simulate` and `DebugControl`, the
  client through its mock (`scripts/uschovna/run-tests.sh`).

## Safety constraints

- **`main` is the release branch.** Every push to `main` publishes a GitHub Release. Never commit to
  `main`, never push it, never merge into it on your own judgement.
- **A real upload is a real send** from the maintainer's address, with a control email. Of the
  five test uploads the maintainer approved on 2026-10-04, three were used; ask before any further
  real upload.
- **Be a polite client.** No bulk sending, no parallel hammering, no load tests against Úschovna.
- **The sender email lives in the app's settings on the Mac, never in the repo.**
- **Never log, store or share the part of a finish code after its slash.**
- **The Sparkle key can't be replaced.** Every installed copy accepts only updates signed with it;
  losing it means everyone reinstalls by hand once. Agents never export, print or store it.
