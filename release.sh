#!/bin/bash
# Prepares a release: builds Typo, zips it, signs the zip for Sparkle and adds it to docs/appcast.xml.
#
#   ./release.sh 0.2
#
# The version must match MARKETING_VERSION in project.yml; raise CURRENT_PROJECT_VERSION there for every release.
# Publishing stays manual: the script prints the two commands that upload the zip and the appcast.
# Signing needs the key that `generate_keys --account typo` created in the login keychain. Back it up with
# `generate_keys --account typo -x typo-sparkle-key.txt` and keep that file somewhere safe and private.
set -euo pipefail
cd "$(dirname "$0")"

version=${1:?Usage: ./release.sh <version>, for example ./release.sh 0.2}
marketing=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
[[ $version == "$marketing" ]] || { echo "project.yml has MARKETING_VERSION $marketing, not $version." >&2; exit 1; }
grep -q "<sparkle:version>$build</sparkle:version>" docs/appcast.xml 2>/dev/null &&
    { echo "Build $build is already in the appcast. Raise CURRENT_PROJECT_VERSION in project.yml." >&2; exit 1; }

./build.sh

zip=build/Typo-$version.zip
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent build/Typo.app "$zip"

sparkle=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
signature=$("$sparkle/sign_update" --account typo "$zip")    # prints: sparkle:edSignature="…" length="…"

url="https://github.com/scholzdev/typo/releases/download/v$version/Typo-$version.zip"
item="    <item>
      <title>Typo $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://scholzdev.github.io/typo/guide/release-notes.html</sparkle:releaseNotesLink>
      <enclosure url=\"$url\" $signature type=\"application/octet-stream\"/>
    </item>"

if [[ ! -f docs/appcast.xml ]]; then
    cat > docs/appcast.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Typo</title>
  </channel>
</rss>
EOF
fi
# The newest release goes first, right after the channel title.
ITEM="$item" perl -0pi -e 's|(<title>Typo</title>\n)|$1$ENV{ITEM}\n|' docs/appcast.xml

printf '\nPrepared %s and added it to docs/appcast.xml. To publish:\n\n' "$zip"
echo "  gh release create v$version $zip --title \"Typo $version\""
echo "  git add docs/appcast.xml && git commit -m \"Typo $version\" && git push"
