#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
source "$repo_root/scripts/release-config.sh"

test_root=$(mktemp -d -t agent-session-manager-release-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/site" "$test_root/input"
printf 'fixture-dmg' > "$test_root/input/AgentSessionManager-0.0.1-1.dmg"
cp "$repo_root/appcast.xml" "$test_root/input/appcast.xml"

"$repo_root/scripts/validate-sparkle-key.sh" >/dev/null

fixture_private_key=$(ruby -rbase64 -e 'puts Base64.strict_encode64("\0" * 32)')
fixture_public_key=$(SPARKLE_PRIVATE_KEY="$fixture_private_key" ruby -rbase64 -ropenssl -e '
  seed = Base64.strict_decode64(ENV.fetch("SPARKLE_PRIVATE_KEY"))
  der = ["302e020100300506032b657004220420"].pack("H*") + seed
  puts Base64.strict_encode64(OpenSSL::PKey.read(der).public_to_der.byteslice(-32, 32))
')
printf '%s\n' "$fixture_public_key" > "$test_root/input/sparkle-public.pem"
SPARKLE_PUBLIC_KEY_FILE="$test_root/input/sparkle-public.pem" \
    SPARKLE_PRIVATE_KEY="$fixture_private_key" \
    "$repo_root/scripts/validate-sparkle-key.sh" >/dev/null

printf '%s\n' "${fixture_public_key%?}" > "$test_root/input/sparkle-public.pem"
if SPARKLE_PUBLIC_KEY_FILE="$test_root/input/sparkle-public.pem" \
    "$repo_root/scripts/validate-sparkle-key.sh" >/dev/null 2>&1; then
    echo "Sparkle key validation accepted malformed public material" >&2
    exit 1
fi

printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    > "$test_root/input/sparkle-public.pem"
if SPARKLE_PUBLIC_KEY_FILE="$test_root/input/sparkle-public.pem" \
    SPARKLE_PRIVATE_KEY="$fixture_private_key" \
    "$repo_root/scripts/validate-sparkle-key.sh" >/dev/null 2>&1; then
    echo "Sparkle key validation accepted mismatched signing material" >&2
    exit 1
fi

legacy_private_key=$(ruby -rbase64 -e 'puts Base64.strict_encode64("\0" * 96)')
if SPARKLE_PRIVATE_KEY="$legacy_private_key" \
    "$repo_root/scripts/validate-sparkle-key.sh" >/dev/null 2>&1; then
    echo "Sparkle key validation accepted unsupported legacy key material" >&2
    exit 1
fi

"$repo_root/scripts/stage-pages-assets.sh" \
    "$test_root/site" release \
    "$test_root/input/AgentSessionManager-0.0.1-1.dmg" \
    "$test_root/input/appcast.xml"

cmp \
    "$test_root/site/downloads/AgentSessionManager-0.0.1-1.dmg" \
    "$test_root/site/downloads/AgentSessionManager-latest.dmg"
test -f "$test_root/site/appcast.xml"
test "$(git -C "$repo_root" ls-files '*.dmg')" = ""

cat > "$test_root/input/published-appcast.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item><sparkle:version>250</sparkle:version></item>
  </channel>
</rss>
EOF

test "$(RELEASE_APPCAST_PATH="$test_root/input/published-appcast.xml" \
    "$repo_root/scripts/release-build-number.sh" 227)" = "251"

if APPCAST_BASE="$test_root/input/published-appcast.xml" \
    APPCAST_OUTPUT="$test_root/output-appcast.xml" \
    "$repo_root/scripts/update-appcast.sh" \
    "$test_root/input/AgentSessionManager-0.0.1-1.dmg" 0.0.3 225 >/dev/null 2>&1; then
    echo "appcast accepted a build version older than a published release" >&2
    exit 1
fi

plist_minimum=$(grep -A1 "<key>LSMinimumSystemVersion</key>" "$repo_root/Info.plist" | sed -n "s:.*<string>\\(.*\\)</string>.*:\\1:p")
test "$plist_minimum" = "26.0"
grep -q "sparkle:minimumSystemVersion>\$minimum_system_version<" "$repo_root/scripts/update-appcast.sh"

if rg -n 'github\.com/JustinDFuller/agent-session-manager/releases|justinfuller\.github\.io' \
    "$repo_root/index.md" \
    "$repo_root/documentation/tutorials" \
    "$repo_root/documentation/how-to" \
    "$repo_root/documentation/reference" \
    "$repo_root/documentation/explanation" \
    "$repo_root/appcast.xml" \
    "$repo_root/scripts" \
    "$repo_root/documentation/features/distribution.md"; then
    echo "public release copy contains a private or obsolete URL" >&2
    exit 1
fi

echo "Release publication contract passed."
