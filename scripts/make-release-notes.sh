#!/bin/bash
# Writes the release notes, build/release/notes.md: the feat, fix and perf commits since the last
# release, without their prefixes, one per line.
#
#   scripts/make-release-notes.sh
#
# The last release is the newest v* tag behind HEAD; without one, it's every commit. Run it after
# scripts/build-release.sh, which empties build/release.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build/release
mkdir -p "$out"

previous=$(git -C "$root" describe --tags --abbrev=0 --match 'v*' HEAD 2> /dev/null || true)
notes=$(git -C "$root" log --no-merges --reverse --format=%s ${previous:+"$previous..HEAD"} \
  | sed -nE 's/^(feat|fix|perf)(\([^)]*\))?!?: //p' \
  | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }')
[[ -n $notes ]] || notes="- Changes behind the scenes only."
printf '%s\n' "$notes" > "$out/notes.md"

echo "$out/notes.md"
