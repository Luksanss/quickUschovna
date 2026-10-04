#!/bin/sh
# Builds the app's Úschovna client with the app's Swift settings into a test harness and runs it
# against the local mock server. Nothing is sent to uschovna.cz.
#
#   scripts/uschovna/run-tests.sh                 all scenarios
#   scripts/uschovna/run-tests.sh "small file"    only the named ones
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$root/build/uschovna-tests"
rm -rf "$work"
mkdir -p "$work"

# The app target's settings: Swift 6, MainActor by default, approachable concurrency.
xcrun swiftc -O -warnings-as-errors \
  -swift-version 6 \
  -default-isolation=MainActor \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -module-name quickUschovna \
  "$root/quickUschovna/Model/UploadService.swift" \
  "$root/quickUschovna/Model/Package.swift" \
  "$root"/quickUschovna/Uschovna/*.swift \
  "$root/scripts/uschovna/main.swift" \
  -o "$work/harness"

python3 "$root/scripts/uschovna/mock_server.py" --www-port 0 --upload-port 0 \
  --store "$work/store" --ready-file "$work/ready.json" > "$work/mock.log" 2>&1 &
mock=$!
trap 'kill "$mock" 2>/dev/null || true; rm -rf "$work/store"' EXIT INT TERM

tries=0
until [ -f "$work/ready.json" ]; do
  tries=$((tries + 1))
  if [ "$tries" -gt 100 ]; then
    echo "The mock server didn't start:" >&2
    cat "$work/mock.log" >&2
    exit 1
  fi
  sleep 0.1
done
port="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["www"])' "$work/ready.json")"

status=0
"$work/harness" "http://127.0.0.1:$port" "$@" || status=$?
echo "Mock server log: $work/mock.log"
exit "$status"
