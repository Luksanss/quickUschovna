---
name: handoff
description: "Start-of-session orientation. Reads the handoff document and the real git state, verifies the one against the other, and says whether the next piece of work can start. Use when the user asks where we left off, what the current state is, or whether we are ready to implement something."
allowed-tools: Read Grep Glob Bash(git *) Bash(ls *) Bash(cat *) Bash(gh pr list *)
---

# /handoff — where did we leave off?

Work named by the user (may be empty): `$ARGUMENTS`

## Handoff document
!`f=$(ls docs/handoff.md handoff.md HANDOFF.md 2>/dev/null | head -1); echo "path: ${f:-NONE FOUND}"; echo; cat "$f" 2>/dev/null`

## Git state
!`echo "branch: $(git branch --show-current)"; echo; echo "--- working tree ---"; git status --short; echo "(empty = clean)"; echo; echo "--- remotes ---"; git remote -v | head -2; echo "(empty = no remote yet)"; echo; echo "--- last 12 commits on main ---"; git log --oneline -12 main 2>/dev/null; echo; echo "--- on dev, not yet released to main ---"; git log --oneline main..dev 2>/dev/null; echo; echo "--- main vs origin/main, dev vs origin/dev (ahead behind, as of last fetch) ---"; echo "main: $(git rev-list --left-right --count main...origin/main 2>/dev/null)"; echo "dev:  $(git rev-list --left-right --count dev...origin/dev 2>/dev/null)"; echo; echo "--- open dev -> main pull request ---"; gh pr list --base main --head dev --json number,title,url --jq '.[] | "#\(.number) \(.title) \(.url)"' 2>/dev/null; echo "(empty = none, or no remote)"; echo; echo "--- branches other than main and dev ---"; git branch --format='%(refname:short)' | grep -v -E '^(main|dev)$'`

## What to do

Everything above is already loaded; do not re-run it.

Work through these checks silently, then report using the template below and nothing else.

- **Verify the handoff against git; never restate it as fact.** Commits it names still exist?
  Anything it calls "uncommitted" or "on `dev`" now in `main`? Commits on `main` or `dev` it does
  not know about? Local `main` or `dev` behind origin (you may not `fetch`, tell them to)?
  Paragraphs it marks as spent?
- **Did the assumed release land?** At a release, `/handoff-update` archives the spent handoff and
  writes the new one as if `dev` has been merged into `main`, because the maintainer normally
  merges right after. Check the claim, not the archive: is the work it reports as released
  actually in `origin/main`? If not, say so plainly; the handoff is overstating reality and the
  pull request is still open or was never opened. Only if an archive is genuinely missing for a
  release that did land, offer to write it; never unasked.
- **Branch model.** This repo has only `dev` and `main`. Any other branch is a leftover to
  mention, not a place to work.
- **Readiness.** On `main`? Work happens on `dev`, so a switch is needed before any edit.
  Uncommitted changes? An open question in Next action that blocks scope (for example an
  unanswered feasibility question that gates design or implementation)?

## Name the session before you answer

This skill is almost always the session's first message, so the app titles the whole session
"Handoff", and a sidebar of identical "Handoff" rows is useless a week later, when the thing
worth finding is *which* session touched *what*. If a session-management tool is available
(`mcp__ccd_session_mgmt__set_session_title`, `session_id: "self"`), rename it as the last
thing before you print the report.

Title it after the work this session is about to do, not after the orientation: two to four
words of what it is. With nothing named, use the next action from the handoff. If the answer is
"blocked", say that instead. Keep it under about 30 characters of signal; sidebars truncate. If
the rename is declined because the user titled the session themselves, drop it silently and print
the report.

## Output — this template, in English, nothing before or after it

**State**
- last landed: <one line>
- in flight: <one line, or "nothing">
- next per handoff: <one line, or "none named">

**Handoff vs git** — omit the section entirely if consistent; otherwise a table, only the
mismatches:

| Handoff says | Actually |
|---|---|
| <claim, ≤ 10 words> | <fact, ≤ 12 words> |

**Release check:** <one line, only if the assumed release did not land>

**Ready?** — list only the items that fail, one line each. If nothing fails, skip the list.
Then exactly one closing line: **ready** / **ready after: …** / **blocked by: …**

## Rules that keep it short

- Write in English, always. The repo's own content, or the maintainer's messages, may be in
  Czech. That is the subject matter, not a signal about which language to answer in.
- One fact per bullet, one line per bullet. No hashes, PR numbers or file paths unless a
  mismatch hinges on that exact value.
- Do not list things that are fine; the template's silence means "checked, OK".
- Do not propose plans or candidates unless the user named a piece of work.
- Target: the whole reply fits on one screen (≈ 20 lines). Details are available on request.
- The rename is a tool call, not text. "Nothing before or after the template" is about what
  you print; do not announce the rename or mention the new title in the reply.
- Stop after the closing line. Do not implement, run checks, or switch branches.
