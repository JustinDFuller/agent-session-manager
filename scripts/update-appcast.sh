#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
source "$repo_root/scripts/release-config.sh"

if [ $# -ne 3 ]; then
    echo "usage: $0 <dmg-path> <short-version> <build-number>" >&2
    exit 1
fi

dmg_path=$1
version_short=$2
version_build=$3
dmg_name=$(basename "$dmg_path")
download_url="$PUBLIC_SITE_URL/$PUBLIC_DOWNLOADS_PATH/$dmg_name"

if [ ! -f "$dmg_path" ]; then
    echo "ERROR: DMG not found: $dmg_path" >&2
    exit 1
fi

base_appcast="${APPCAST_BASE:-$repo_root/appcast.xml}"
appcast="${APPCAST_OUTPUT:-$repo_root/appcast.xml}"

if [ ! -f "$base_appcast" ]; then
    echo "ERROR: appcast.xml not found at $base_appcast" >&2
    exit 1
fi

if [[ ! "$version_build" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Sparkle build version must be a non-negative integer: $version_build" >&2
    exit 1
fi

minimum_build=$(RELEASE_APPCAST_PATH="$base_appcast" \
    "$repo_root/scripts/release-build-number.sh" 0)
if (( version_build < minimum_build )); then
    echo "ERROR: Sparkle build version $version_build must be at least $minimum_build" >&2
    exit 1
fi

signature=$("$repo_root/scripts/sign-update.sh" "$dmg_path")
file_size=$(stat -f%z "$dmg_path")
pub_date=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
minimum_system_version=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$repo_root/Info.plist")

mkdir -p "$(dirname "$appcast")"

item="    <item>
      <title>Agent Session Manager $version_short</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$version_build</sparkle:version>
      <sparkle:shortVersionString>$version_short</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system_version</sparkle:minimumSystemVersion>
      <enclosure url=\"$download_url\" length=\"$file_size\" type=\"application/octet-stream\" sparkle:edSignature=\"$signature\" />
    </item>"

ruby -e '
  base_path, output_path, item = ARGV
  content = File.binread(base_path)
  marker = "</channel>"
  abort "appcast is missing </channel>" unless content.include?(marker)
  File.binwrite(output_path, content.sub(marker, "#{item}\n#{marker}"))
' "$base_appcast" "$appcast.tmp" "$item"
mv "$appcast.tmp" "$appcast"

echo "Updated $appcast with v$version_short"
