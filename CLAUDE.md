# quickUschovna

A macOS menu-bar app for sending files through [uschovna.cz](https://www.uschovna.cz): drag files
anywhere and drop them on the zone that opens under the menu-bar icon (or use Finder's Quick
Actions › Send with Úschovna), and the share link lands on the clipboard, with the sender email set
once. It's the maintainer's second menu-bar app after betterTab (`../betterTab`), and follows its
conventions.

## Start here

Read `docs/handoff.md` first. It has the brief, the current state, the next action, the decisions
already settled and the findings behind them. It's verified against git by `/handoff` and
rewritten by `/handoff-update`; both skills live in `.claude/skills/`. Then read:
- `docs/spec.md`: exactly what the app does. It's the source of truth for behaviour and scope; the
  design it implements one to one is `design/prototype/quickUschovna v1.dc.html`.
- `docs/architecture.md`: how it's built.
- `docs/uschovna-protocol.md`: Úschovna's upload protocol as the client speaks it.
- `docs/quick-action.md` and `docs/releasing.md`: the Finder Quick Action, and how releases happen.

## Branches, commits and handoffs

One developer, one user, so keep it simple.
- **Work happens on `dev`.** Commit straight to it, with no feature branches. Use Conventional
  Commits and no AI attribution.
- **`main` is the release branch.** It moves only when the maintainer says a version works, by
  merging `dev` through a pull request with a merge commit (not a squash). Once CD exists, a push
  to `main` publishes a GitHub Release.
- **Agents may push `dev` and open the `dev` → `main` pull request.** Agents never merge it,
  and never commit or push to `main`.
- **Archive a handoff only at a release:** copy `docs/handoff.md` to
  `docs/archive/handoffs/<ISO date>.md`, adding a topical suffix if the date is taken. Between
  releases, `/handoff-update` rewrites `docs/handoff.md` in place and writes no archive.
- **No CI; checks run locally.** The required checks are a clean build of the quickUschovna scheme,
  Debug and Release, with no warnings in our code (the `appintentsmetadataprocessor` "Metadata
  extraction skipped" lines aren't ours), and the Úschovna client's scenarios against the local
  mock server, which sends nothing to Úschovna. The `.noindex` suffix keeps dev builds out of
  Spotlight.
  ```
  for c in Debug Release; do xcodebuild -project quickUschovna.xcodeproj -scheme quickUschovna -configuration $c -derivedDataPath build/DerivedData.noindex build | grep -E 'error|warning: |BUILD' ; done
  scripts/uschovna/run-tests.sh
  ```
- **Debug builds can be driven without a mouse.** `--simulate [MB/s]` replaces Úschovna with a
  stand-in that sends nothing and keeps its own settings; `xcrun swift scripts/debug-control.swift
  <command>` sends it commands (`send`, `drag`, `over`, `panel`, `dump <file>`…, listed in
  `quickUschovna/App/DebugControl.swift`).

## Rules that are expensive to forget

- **The repository is public.** Anyone can read every commit. No keys, tokens, certificates or
  personal email addresses in the repo; release secrets live only in the GitHub `release`
  environment, which the maintainer manages. Agents never handle signing keys. The Team ID in
  `project.pbxproj` is fine: every signed app carries it in its signature anyway.
- **Stay minimal.** The point of the app is fewer steps than the website. Every screen, field and
  click needs a reason.
- **Úschovna has no API and the app is unofficial.** It uses the website's own upload; their terms
  don't forbid a personal client, but don't allow one either, and they can change it any day
  (`docs/handoff.md` § Findings). Keep `README.md` honest about that, and keep the client polite:
  no bulk sending, no load tests.
- **A real upload is a real send** from the maintainer's address. Agents don't trigger one unless
  the maintainer asks for that one upload.
- **The sender email lives in the app's settings, never in the repo.**
