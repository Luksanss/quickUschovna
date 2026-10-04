#!/bin/bash
# Builds quickUschovna (Release) into a disk image, build/release/quickUschovna-<version>.dmg: the
# app, a link to Applications, and the background from design/dmg/.
#
#   scripts/build-release.sh <version> <build> [signing identity]
#
# The arguments can also come from VERSION, BUILD_NUMBER and SIGNING_IDENTITY.
#
# The app embeds the Finder Quick Action, QuickAction.appex, and the two are signed differently:
# the extension is sandboxed and the app isn't. Xcode builds both and signs them ad hoc, with the
# entitlements it derives from each target's build settings. This script then signs them again,
# inside out: the extension with its own entitlements, then the app with its own, both with the
# hardened runtime. Never --deep, which would sign the extension with the app's entitlements and
# take its sandbox away. With an identity, that's the identity (an Apple Development certificate
# of team 5KDU5HYH35); without one, it's ad hoc, and macOS may not load the extension of an ad-hoc
# app (docs/releasing.md § Signing).
#
# dmgbuild lays out the image's window; it's installed by hash into build/dmgbuild, with
# Python 3.10 or later.
set -euo pipefail

version=${1:-${VERSION:-}}
build=${2:-${BUILD_NUMBER:-}}
identity=${3:-${SIGNING_IDENTITY:-}}
[[ -n $version && -n $build ]] || { echo "usage: $0 <version> <build> [signing identity]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
derived=$root/build/release-DerivedData.noindex # .noindex keeps Spotlight from listing it
out=$root/build/release
app=$derived/Build/Products/Release/quickUschovna.app
extension=$app/Contents/PlugIns/QuickAction.appex
dmg=$out/quickUschovna-$version.dmg
log=$out/build.log
venv=$root/build/dmgbuild
requirements=$root/scripts/dmgbuild-requirements.txt

# Start clean, so every file compiles and every warning shows up.
rm -rf "$derived" "$out"
mkdir -p "$out"

# Ad hoc for now; the signature that ships is made below.
xcodebuild -quiet -project "$root/quickUschovna.xcodeproj" -scheme quickUschovna -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" \
  build 2>&1 | tee "$log"

# A warning in a file under the repo is ours, and a release doesn't ship with one.
if grep -F ': warning: ' "$log" | grep -F "$root/"; then
  echo "error: the build has warnings in our code (above)" >&2
  exit 1
fi

# The extension is the only code nested in the app. Anything else would keep Xcode's ad-hoc
# signature, so it has to be signed here first.
nested=$(cd "$app/Contents" && find . -mindepth 1 \( -name '*.appex' -o -name '*.app' -o -name '*.xpc' \
  -o -name '*.framework' -o -name '*.dylib' \) -prune -print)
if [[ $nested != ./PlugIns/QuickAction.appex ]]; then
  printf 'error: build-release.sh signs only PlugIns/QuickAction.appex inside the app, and found:\n%s\n' \
    "$nested" >&2
  exit 1
fi

# Each part keeps the entitlements Xcode signed it with, which Xcode derives from the target's
# build settings (ENABLE_APP_SANDBOX and the like), except get-task-allow: Xcode adds that to every
# build, and it would let any debugger attach to the release.
entitlements() { # <bundle> <file to write them to, left out if there are none>
  codesign -d --entitlements "$2" --xml "$1" 2> /dev/null
  [[ -s $2 ]] || return 0
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$2" > /dev/null 2>&1 || true
  [[ $(plutil -convert json -o - "$2") != '{}' ]] || rm "$2"
}
entitlements "$extension" "$out/QuickAction.entitlements"
entitlements "$app" "$out/quickUschovna.entitlements"
# Finder doesn't load an app extension that isn't sandboxed.
[[ $(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$out/QuickAction.entitlements" \
  2> /dev/null) == true ]] || { echo "error: QuickAction.appex isn't sandboxed" >&2; exit 1; }

# Inside out: the extension, then the app, whose seal covers the extension's new signature.
# --timestamp=none, like Xcode's own signing with a development certificate: no trip to Apple.
sign() { # <bundle> <entitlements file, if there is one>
  local options=(--force --sign "${identity:--}" --options runtime --timestamp=none)
  [[ -f $2 ]] && options+=(--entitlements "$2")
  codesign "${options[@]}" "$1"
}
sign "$extension" "$out/QuickAction.entitlements"
sign "$app" "$out/quickUschovna.entitlements"
rm -f "$out/QuickAction.entitlements" "$out/quickUschovna.entitlements"

codesign --verify --strict --deep "$app"
# What each part was signed with. Not the certificate's name: it holds an email address, and the
# workflow's logs are public.
for code in "$app" "$extension"; do
  details=$(codesign -dv "$code" 2>&1)
  flags=$(sed -nE 's/^CodeDirectory .*flags=0x[0-9a-f]+\(([^)]*)\).*/\1/p' <<< "$details")
  [[ ,$flags, == *,runtime,* ]] || { echo "error: $code doesn't have the hardened runtime" >&2; exit 1; }
  echo "${code#"$(dirname "$app")/"}"
  echo "  $(grep -E '^Identifier=' <<< "$details"), $(grep -E '^TeamIdentifier=' <<< "$details"), flags: $flags"
  granted=$(codesign -d --entitlements - --xml "$code" 2> /dev/null | plutil -p - 2> /dev/null || true)
  if [[ -n $granted ]]; then
    echo "  entitlements:"
    sed 's/^/    /' <<< "$granted"
  else
    echo "  entitlements: none"
  fi
done

# The venv outlives the clean above, and is rebuilt when the pinned requirements change.
if ! cmp -s "$requirements" "$venv/requirements.txt"; then
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || { echo "error: dmgbuild needs Python 3.10 or later, and python3 is $(python3 --version)" >&2; exit 1; }
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes -r "$requirements"
  cp "$requirements" "$venv/requirements.txt"
fi
"$venv/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
  -D "app=$app" -D "background=$root/design/dmg/background.png" quickUschovna "$dmg"

echo "$dmg"
shasum -a 256 "$dmg" | cut -d ' ' -f 1
