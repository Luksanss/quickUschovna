#!/bin/bash
# Signs the release disk image for Sparkle and writes the feed Check for Updates… reads,
# build/release/appcast.xml, which is published beside the disk image. Run it after
# scripts/build-release.sh and scripts/make-release-notes.sh; the notes go into the feed.
#
#   scripts/make-appcast.sh <version> <build> [< private-key]
#
# The arguments can also come from VERSION and BUILD_NUMBER. On CI the EdDSA private key comes on
# stdin, so it's never on a command line or in a file; run by hand with nothing piped in, it's
# read from the login keychain, under the account generate_keys --account quickUschovna made
# (the default account holds betterTab's key). The signature is checked against the public key in
# the built app before anything is written.
set -euo pipefail

version=${1:-${VERSION:-}}
build=${2:-${BUILD_NUMBER:-}}
[[ -n $version && -n $build ]] || { echo "usage: $0 <version> <build> [< private-key]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
derived=$root/build/release-DerivedData.noindex
info=$derived/Build/Products/Release/quickUschovna.app/Contents/Info.plist
sparkle=$derived/SourcePackages/artifacts/sparkle/Sparkle/bin
out=$root/build/release
dmg=$out/quickUschovna-$version.dmg

[[ -f $dmg ]] || { echo "error: there's no $dmg; run scripts/build-release.sh first" >&2; exit 1; }
[[ -f $out/notes.md ]] || { echo "error: there's no $out/notes.md; run scripts/make-release-notes.sh first" >&2; exit 1; }

if [[ -t 0 ]]; then
  signature=$("$sparkle/sign_update" --account quickUschovna -p "$dmg")
else
  signature=$("$sparkle/sign_update" --ed-key-file - -p "$dmg")
fi
xcrun swift "$root/scripts/check-update-signature.swift" "$dmg" "$signature" "$info"
length=$(stat -f %z "$dmg")

# The app's feed is the latest release's appcast.xml, so this release's files sit beside it.
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")
releases=${feed%/latest/download/appcast.xml}
[[ $releases != "$feed" ]] || { echo "error: SUFeedURL isn't a GitHub latest-release URL: $feed" >&2; exit 1; }
url=$releases/download/v$version/quickUschovna-$version.dmg
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")

notes=$(< "$out/notes.md")
notes=${notes//]]>/]] >} # the one string CDATA can't hold

cat > "$out/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>quickUschovna</title>
    <item>
      <title>quickUschovna $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$notes
]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$out/appcast.xml"

echo "$out/appcast.xml"
