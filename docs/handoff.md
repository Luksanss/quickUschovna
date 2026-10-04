# Handoff

Rewritten 2026-10-04 after release 1. **v1.0.43** is out: `dev` went into `main` through pull
request #1, the Release run published the disk image, and the maintainer installed it. Using it,
they found that the drop zone opened for every file drag, moving files around in Finder included
("triggeruje se to pořád a není to dobrý UX"). `dev` first opened it only on the menu-bar icon;
the maintainer tried that ("funguje") and recorded the drag running into the top of the screen
and opening Mission Control. So `dev` now opens the zone when a drag comes **near** the icon, the
maintainer's pick of the options offered. That is built and checked and waits to be tried.
Release 1's archive is `docs/archive/handoffs/2026-10-04.md` (v1 as built and tested); the
handoff this one replaces, written for the release itself, is in git at `003dcbb`.

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

- **`main`** is release 1: the merge commit `a860dd9` of pull request #1, tag `v1.0.43`. Its
  Release run succeeded; the disk image is on the Releases page, signed with the Apple Development
  certificate.
- **`dev`** is release 1 plus the near-the-icon drop zone and this handoff. The icon-only step
  was folded into that one `fix` commit before anything was pushed, so the release notes don't
  list it. `dev` doesn't contain `main`'s merge commit, which is fine: the next pull request
  merges the same way.
- **On the maintainer's Mac:** v1.0.43 is installed in `/Applications`, quit for testing. A Debug
  build with `--simulate` is running, restarted by the agent on the near-the-icon build. Whether
  Launch at Login was tried from the installed app isn't known.
- **Two copies of the Quick Action are registered** with PlugInKit: the installed one (1.0.43) and
  the one in `build/DerivedData.noindex`'s Release build (1.0), which every run of the required
  checks registers again. PlugInKit elects the installed one (`pluginkit -mvvv -i
  com.luksanss.quickUschovna.QuickAction`, without `-A`, checked after a rebuild on 2026-10-04).
  If Finder ever launches a DerivedData build instead, `lsregister -u` that build.

## Next action

1. **The maintainer tries the near-the-icon zone by hand,** in the running Debug build (with the
   installed app quit, so there's one icon; to start it again:
   `open -n build/DerivedData.noindex/Build/Products/Debug/quickUschovna.app --args --simulate`,
   which sends nothing):
   - drag files around Finder, away from the icon: the zone stays shut;
   - drag a file up towards the icon: the zone opens before the menu bar, and a drop on it sends
     without Mission Control;
   - move one of the desktop's top-right icons a little: the zone stays shut;
   - drop straight on the icon: it sends;
   - open the zone, then let go somewhere else: it closes.
   If 80 pt (`SurfaceMetrics.dropZoneApproach`) feels too eager or too late, that's the number.
2. **If it works, the agent opens the `dev` → `main` pull request.** Merged as it stands, it
   publishes v1.0.46, with "Open the drop zone as a file drag comes near the menu-bar icon" as
   its note. That merge is a release, so the next `/handoff-update` archives this file.
3. **The backlog** (Known gaps), in no fixed order; the maintainer picks.

## Decisions already settled

- **v1 is Claude Design's final design, built one to one**; differences are listed in
  `docs/spec.md`. A native client of Úschovna's website upload, behind `UploadService`. One public
  link per drop. Folders zipped by our own stored writer. No in-app updater: releases are a disk
  image without Sparkle. Release builds re-signed without `get-task-allow`. Formats follow the
  system locale. The reasons are in the archived handoff.
- **The drop zone opens when a file drag comes near the icon, not when it starts** (the
  maintainer, 2026-10-04, after using v1.0.43). The prototype opens it for any file drag, which on
  a real desktop got in the way. Opening only on the icon itself was tried and dropped: reaching
  the menu bar runs the drag into the top of the screen, and macOS opens Mission Control. The
  options offered were near the icon, icon only with the macOS setting switched off (which only
  helps this Mac), and back to any drag; the maintainer picked near the icon. Once open, the zone
  stays until the drag ends. `DragMonitor` still follows every file drag and measures its files,
  so the label and size are ready when the zone appears.
- **The repository is public.** Nothing secret in it; release secrets live only in the `release`
  environment, which only `main` can use. The Team ID in `project.pbxproj` is fine.
- **Branches: `dev` and `main` only;** no CI, only CD; the agent may push `dev` and open the
  `dev` → `main` pull request, never merge it or push `main`. Merge with a merge commit.

## Findings worth keeping

- **Úschovna's protocol and what the real server does** are in `docs/uschovna-protocol.md`. The
  three that matter most:
  - it answers `"status": true` where the page checks `1 == status`;
  - the finish code is `<public>/<secret>`, and only `https://www.uschovna.cz/zasilka/<public>/`
    may be shared, because the secret opens the sender's page with "SMAZAT ZÁSILKU";
  - the recipients' page shows the sender's address.
- **The macOS findings** (zip tools, protected folders, the Quick Action arriving switched off,
  worktree builds registering copies of the extension, what the agent can capture but not click)
  are in the archived handoff, § Findings.
- **A file drag that touches the top of the screen opens Mission Control** with macOS's default
  settings (Desktop & Dock's "Drag windows to top of screen to enter Mission Control" is unset in
  `com.apple.dock`, so on). Seen in the maintainer's recording of 2026-10-04, about 0.1 s after the
  pointer reached the top edge. An app can't stop it, only keep the drop below the menu bar.
- **A real drag can only be tried by hand.** The agent can't post mouse events, so the path a real
  drag takes (`DragMonitor`'s global monitors, then `FileDrop` on the status item's window) is
  untested by the agent, and so is opening near the icon, which reads the pointer's position.
  `DebugControl` plays the model's side: `drag <path>`, `icon`, `unicon`, `over`, `out`,
  `enddrag`, with `dump <file>` showing the zone's window. Played on 2026-10-04, the zone stayed
  hidden after `drag`, opened at `icon`, stayed through `unicon` and `over`, and closed at
  `enddrag`.

## Known gaps

- **Nothing is notarized,** so first launch needs Open Anyway.
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
