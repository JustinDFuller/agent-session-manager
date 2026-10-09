#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d -t agent-session-manager-hook-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/empty-hooks"
git init --quiet "$test_root/outer"
git init --quiet "$test_root/nested"
git init --quiet --bare "$test_root/remote.git"
for repository in outer nested; do
    git -C "$test_root/$repository" config core.hooksPath "$test_root/empty-hooks"
    git -C "$test_root/$repository" config user.name "Hook Test"
    git -C "$test_root/$repository" config user.email "hook-test@example.com"
done

export TASK_HOOK_NEXT_REPO="$test_root/nested"
export TASK_HOOK_MARKER="$test_root/check-invoked"
cat > "$test_root/bin/check-runner" <<'EOF'
#!/bin/sh
set -e
case "${0##*/}" in
    swift)
        test "$#" -eq 1 && test "$1" = test
        ;;
    make)
        test "$#" -eq 1 && test "$1" = test-ui-dev-launch
        ;;
    swift-format|swiftlint)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
if test -e "$TASK_HOOK_MARKER"; then
    echo 'Validation hook recursed into its Git fixture' >&2
    exit 1
fi
touch "$TASK_HOOK_MARKER"
git -C "$TASK_HOOK_NEXT_REPO" commit --quiet --allow-empty -m fixture
echo "Test Suite 'All tests' passed"
EOF
chmod +x "$test_root/bin/check-runner"
for runner in swift make swift-format swiftlint; do
    ln -s check-runner "$test_root/bin/$runner"
done
export PATH="$test_root/bin:$PATH"

expected_commits=0
for configuration in commandline environment; do
    for operation in commit push; do
        rm -f "$TASK_HOOK_MARKER"
        if [[ "$operation" == commit ]]; then
            arguments=(commit --quiet --allow-empty -m outer)
        else
            arguments=(push --quiet "$test_root/remote.git" HEAD:main)
        fi
        if [[ "$configuration" == commandline ]]; then
            git -C "$test_root/outer" -c core.hooksPath="$repo_root/.githooks" "${arguments[@]}"
        else
            GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$repo_root/.githooks" \
                git -C "$test_root/outer" "${arguments[@]}"
        fi
        test -f "$TASK_HOOK_MARKER"
        expected_commits=$((expected_commits + 1))
        test "$(git -C "$test_root/nested" rev-list --count HEAD)" -eq "$expected_commits"
    done
done

echo 'Git hook fixture isolation and Dev command routing checks passed.'
