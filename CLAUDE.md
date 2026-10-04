# quickUschovna

A macOS menu-bar app, not built yet, for sending files through
[uschovna.cz](https://www.uschovna.cz): drag files onto the menu-bar icon and the share link lands
on the clipboard, with the sender email set once in settings. It's the maintainer's second
menu-bar app after betterTab (`../betterTab`), and follows its conventions.

## Start here

Read `docs/handoff.md` first. It has the brief, the current state, the next action, the decisions
already settled and the findings behind them. It's verified against git by `/handoff` and
rewritten by `/handoff-update`; both skills live in `.claude/skills/`.

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
- **No CI; checks run locally.** There's no required check yet, because there's no project.
  When the Xcode project lands, its clean build becomes one; put the exact command here.

## Rules that are expensive to forget

- **The repository is public.** Anyone can read every commit. No keys, tokens, certificates,
  personal email addresses or Team IDs in the repo; release secrets live only in the GitHub
  `release` environment, which the maintainer manages. Agents never handle signing keys.
- **Stay minimal.** The point of the app is fewer steps than the website. Every screen, field and
  click needs a reason.
- **Úschovna has no API and the app is unofficial.** It uses the website's own upload; their terms
  don't forbid a personal client, but don't allow one either, and they can change it any day
  (`docs/handoff.md` § Findings). Keep `README.md` honest about that, and keep the client polite:
  no bulk sending, no load tests.
- **A real upload is a real send** from the maintainer's address. Agents don't trigger one unless
  the maintainer asks for that one upload.
- **The sender email lives in the app's settings, never in the repo.**
