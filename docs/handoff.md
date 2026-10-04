# Handoff

Written 2026-10-04 for release 1, as if `dev` has been merged into `main`: the maintainer tried v1
by hand ("všechno facha jak má"), set up the `release` environment and its two secrets, and the
agent opened the `dev` → `main` pull request. Merged, it publishes **v1.0.43**, the first release.
`/handoff` checks that against git. The handoff written while v1 was built, with the full account
of how it was made and tested, is archived at `docs/archive/handoffs/2026-10-04.md`.

**The brief.** A macOS menu-bar app that makes sending a file through
[uschovna.cz](https://www.uschovna.cz) take seconds instead of a browser round trip: drag files,
drop them on the zone under the menu-bar icon (or use Finder's Quick Actions › Send with
Úschovna), and the share link is on the clipboard. The sender email is set once. What v1 does is
`docs/spec.md`; how it's built is `docs/architecture.md`; the design it implements one to one is
`design/prototype/quickUschovna v1.dc.html`.

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

- **`main`** should be release 1: `dev` merged through the pull request, with a merge commit, the
  43rd commit, so `v1.0.43`. Until the merge it's still the initial commit.
- **`dev`** holds v1 plus this handoff. Work continues on it.
- **The `release` environment exists** with `main` as its only allowed branch, and both secrets
  are set (`SIGNING_CERT_P12`, `SIGNING_CERT_PASSWORD`), checked on 2026-10-04. The first export
  attempt uploaded an empty `SIGNING_CERT_P12` (the `.p12` hadn't been exported yet); the second
  upload replaced it. If the run says the secret isn't set, that's why.
- **On the maintainer's Mac:** a Debug build from `build/DerivedData.noindex` may still be running,
  with the real sender address set and one test link in Recent (expires 2026-10-18).

## Next action

1. **Check the release run** (Actions → Release): signed with the certificate (the run's summary
   says so), the tag `v1.0.43`, the disk image and its notes on the Releases page.
2. **Install from the disk image** in place of the Debug build: quit the Debug build, install,
   Open Anyway once, tick the Quick Action again only if Finder shows it off, and try Launch at
   Login, which a DerivedData build couldn't register for real.
3. **The backlog** (Known gaps), in no fixed order; the maintainer picks.

## Decisions already settled

- **v1 is Claude Design's final design, built one to one**; differences are listed in
  `docs/spec.md`. A native client of Úschovna's website upload, behind `UploadService`. One public
  link per drop. Folders zipped by our own stored writer. No in-app updater: releases are a disk
  image without Sparkle. Release builds re-signed without `get-task-allow`. Formats follow the
  system locale. The reasons are in the archived handoff.
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

## Known gaps

- **Release 1's run hasn't happened yet,** and nothing is notarized (first launch needs Open
  Anyway).
- **Open protocol questions** (`docs/uschovna-protocol.md`, last section): a chunk sent again after
  a lost answer, above all a file's last chunk; whether `still_alive` matters.
- **Rare failures get the generic message:** over 1000 items in one drop, or only empty files, ends
  in "Úschovna isn’t answering".
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
