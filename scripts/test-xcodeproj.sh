#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d -t agent-session-manager-xcodeproj-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

git init --quiet "$test_root"
mkdir -p "$test_root/Sources"
printf '%s\n' 'let value = 1' > "$test_root/Sources/main.swift"
cat > "$test_root/project.yml" <<'EOF'
name: AgentSessionManager
targets:
  Fixture:
    type: tool
    platform: macOS
    sources: Sources
EOF
cp "$repo_root/Package.resolved" "$test_root/Package.resolved"

cd "$test_root"
make -f "$repo_root/Makefile" GIT_COMMON_ROOT="$test_root" xcodeproj
workspace_lock="$test_root/AgentSessionManager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cmp Package.resolved "$workspace_lock"

printf '%s\n' '{"pins":[],"version":3}' > "$workspace_lock"
make -f "$repo_root/Makefile" GIT_COMMON_ROOT="$test_root" xcodeproj
cmp Package.resolved "$workspace_lock"

rm Package.resolved
if make -f "$repo_root/Makefile" GIT_COMMON_ROOT="$test_root" xcodeproj > "$test_root/missing-lock.log" 2>&1; then
    echo "Xcode generation accepted a missing dependency lockfile" >&2
    exit 1
fi

echo "Xcode dependency lockfile checks passed."
