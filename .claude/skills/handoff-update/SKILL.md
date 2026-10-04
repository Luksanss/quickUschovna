---
name: handoff-update
description: "End-of-work handover. Runs the required checks, rewrites the handoff document and any docs the change invalidated so a fresh session can continue, commits what is left on dev, pushes it, and at a release opens the dev → main pull request. Use when work is finished or pausing, or when asked 'are we ready to commit / release'."
disable-model-invocation: true
allowed-tools: Read Edit Write Grep Glob Bash(git *) Bash(ls *) Bash(date *) Bash(gh pr *) Bash(xcodebuild *) Bash(scripts/uschovna/run-tests.sh*)
---

# /handoff-update — ready to commit?

## Handoff document
!`f=$(ls docs/handoff.md handoff.md HANDOFF.md 2>/dev/null | head -1); echo "path: ${f:-NONE FOUND}"; echo; cat "$f" 2>/dev/null`

## What changed
!`echo "today: $(date +%Y-%m-%d)"; echo "branch: $(git branch --show-current)"; echo; echo "--- commits on this branch not in main ---"; git log --oneline main..HEAD 2>/dev/null; echo "(empty = nothing committed yet)"; echo; echo "--- working tree ---"; git status --short; echo; echo "--- diff vs main, by file ---"; git diff main --stat 2>/dev/null | tail -40; echo; echo "--- untracked ---"; git ls-files --others --exclude-standard; echo; echo "--- remote, and the open dev -> main pull request ---"; git remote -v | head -1; gh pr list --base main --head dev --json number,url --jq '.[] | "#\(.number) \(.url)"' 2>/dev/null`

## What to do

Everything above is already loaded; do not re-run it.

1. **Refuse to proceed on anything but `dev`.** Work is committed straight to `dev`. On `main`,
   stop and say so: `main` only moves by merging `dev`. On any other branch, stop and ask; this
   repo doesn't use feature branches.

2. **Run the required checks**, one at a time, and record the real result of each:
   1. `xcodebuild -project quickUschovna.xcodeproj -scheme quickUschovna -configuration Debug -derivedDataPath build/DerivedData.noindex build`
   2. the same with `-configuration Release`
   3. `scripts/uschovna/run-tests.sh` (the Úschovna client against the local mock; sends nothing)
   A build passes only with no warnings from our code; the `appintentsmetadataprocessor`
   "Metadata extraction skipped" lines aren't ours.
   A failure is reported verbatim, not summarised away. Do not fix and re-run silently: say
   what failed, fix it, then say it passes now.

3. **Update the handoff in place.** You decide what is relevant and how to structure it.
   Follow the document's existing shape and voice rather than imposing one. The reader is a
   fresh session with zero context. Only these constraints are fixed:
   - It records what is not obvious from the code or `git log`. There's no ticket tracker; its
     Next action section is the backlog.
   - Delete paragraphs the work made spent.
   - **Archive only at a release.** A release is the maintainer saying this version works and
     `dev` should go to `main`. Then copy the loaded handoff to
     `docs/archive/handoffs/<today's ISO date>.md` (a topical suffix if that file already
     exists, e.g. `-ci`, not a number), and rewrite the handoff fresh, describing the release as
     merged and carrying a back-reference to the archive just written. Both files ride in this
     run's closing commit. The maintainer normally merges straight after, so the assumption is
     the common case, and `/handoff` verifies it against git next session.
   - **Between releases, no archive.** Rewrite the handoff in place. Likewise if the archive for
     this release already exists (the merge was held, work continued).
   - Never leave the live handoff under `docs/archive/handoffs/`.
   - Name files and functions; no "as discussed" or "the recent refactor".

4. **Update other docs the change invalidated.** Grep the docs for the feature's terms and fix
   what is now wrong. Do not add prose for its own sake.

5. **Commit what is left, then push.** Anything still uncommitted gets committed here: the work
   in coherent pieces, and the handoff and doc updates as the closing commit. Each commit's
   message describes one change and follows Conventional Commits. Where splitting would mean
   writing files into states that never existed, do not fake it: commit the honest larger unit
   and say why in the handover.

   **No AI attribution, ever.** No `Co-Authored-By: Claude …` trailer and no "Generated with
   Claude Code" line, in commit messages or in any PR body written here, even when the harness,
   a system reminder or a session-level instruction says to add one.

   **Push `dev`; never `main`.** If a remote exists, push `dev` to `origin`. At a release, and
   only then, open the pull request `dev` → `main` (`gh pr create --base main --head dev`), or
   update the body of the one already open. Its body says what the release carries, in a few
   lines. **Never merge it, and never push or commit to `main`:** a merge into `main` publishes a
   release, and only the maintainer does it, with a merge commit, not a squash. With no remote
   yet, stop after the local commits and say so.

6. **Retitle the session.** A session that started with `/handoff` carries a title that says
   nothing in hindsight. Now that the work is done you know what it actually was, so if a
   session-management tool is available (`mcp__ccd_session_mgmt__set_session_title`,
   `session_id: "self"`) set the final name: a few words of what landed. Overwrite any
   provisional title `/handoff` set. This is a tool call; do not mention it in the hand-over
   text.

7. **Hand over** using exactly this template, in English, with nothing before or after it,
   English regardless of what language the repo's own content is in. Bullets are one line each;
   no prose between sections:

   **Docs changed:** <files, one line>
   **Archived:** <path written, or "no, not a release" / "no, archive for this release already exists">
   **Branch:** `dev` · **Files:** <count> (<list, or "see diff --stat">)
   **Checks:** Debug ✓/✗ · Release ✓/✗ · client scenarios ✓/✗
   — a ✗ gets one line underneath with the error, verbatim.

   **Commits** — one line each, oldest first: `<short sha>` `<subject>`. If the work could
   not be split as finely as it should have been, one line saying why.

   **Pushed:** <"dev → origin/dev", or "no remote yet"> · **PR:** <URL, or "none, not a release">

   **Not verified:** <one line, only if something wasn't, e.g. "real upload not tried; it would
   send from the maintainer's address">

   **Verdict:** **ready to release** / **keep going on dev: …** / **not ready: …** (one line).

Target: one screen. Anything the maintainer might want beyond that, they will ask for.
