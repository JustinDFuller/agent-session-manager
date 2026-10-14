#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d -t agent-session-manager-hook-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

outer="$test_root/outer"
nested="$test_root/nested"
remote="$test_root/remote.git"
log="$test_root/invocations.log"
markers="$test_root/markers"

mkdir -p "$test_root/bin" "$test_root/empty-hooks" "$markers"
git init --quiet -b main "$outer"
git init --quiet -b main "$nested"
git init --quiet --bare "$remote"
for repository in "$outer" "$nested"; do
    git -C "$repository" config core.hooksPath "$test_root/empty-hooks"
    git -C "$repository" config user.name "Hook Test"
    git -C "$repository" config user.email "hook-test@example.com"
done
git -C "$outer" remote add origin "$remote"

export TASK_HOOK_NEXT_REPO="$nested"
export TASK_HOOK_LOG="$log"
export TASK_HOOK_MARKERS="$markers"
cat > "$test_root/bin/check-runner" <<'EOF'
#!/bin/sh
set -e
name=${0##*/}
line="$name $*"
printf '%s\n' "$line" >> "$TASK_HOOK_LOG"
key=$(printf '%s' "$line" | tr -c 'A-Za-z0-9' _)
if test -e "$TASK_HOOK_MARKERS/$key"; then
    echo "Validation hook recursed into its Git fixture or repeated a check: $line" >&2
    exit 1
fi
touch "$TASK_HOOK_MARKERS/$key"
case "$line" in
    "${TASK_HOOK_FAIL:-@@never@@}"*)
        echo "stubbed failure: $line" >&2
        exit 1
        ;;
esac
if test "$name" = swift-format; then
    touch "$TASK_HOOK_NEXT_REPO/fixture-$$.swift"
    git -C "$TASK_HOOK_NEXT_REPO" add .
    git -C "$TASK_HOOK_NEXT_REPO" commit --quiet -m fixture
fi
if test "$name" = swift; then
    echo "Test Suite 'All tests' passed"
fi
EOF
chmod +x "$test_root/bin/check-runner"
for runner in swift make swift-format swiftlint node openspec; do
    ln -s check-runner "$test_root/bin/$runner"
done
export PATH="$test_root/bin:$PATH"

mkdir -p "$outer/scripts"
for script in test-git-hooks test-release-publishing; do
    printf '#!/bin/sh\necho "fixture-%s" >> "$TASK_HOOK_LOG"\n' "$script" > "$outer/scripts/$script.sh"
    chmod +x "$outer/scripts/$script.sh"
done
git -C "$outer" add .
git -C "$outer" commit --quiet -m baseline
git -C "$outer" push --quiet origin HEAD:main

last_output=""
last_status=0

fail() {
    echo "FAIL (line ${BASH_LINENO[1]}): $*" >&2
    echo "--- hook output:" >&2
    printf '%s\n' "$last_output" >&2
    echo "--- invocations:" >&2
    cat "$log" >&2
    exit 1
}

run_hooked() {
    local configuration=$1
    shift
    : > "$log"
    rm -f "$markers"/*
    set +e
    if [[ "$configuration" == environment ]]; then
        last_output=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$repo_root/.githooks" \
            git -C "$outer" "$@" 2>&1)
    else
        last_output=$(git -C "$outer" -c core.hooksPath="$repo_root/.githooks" "$@" 2>&1)
    fi
    last_status=$?
    set -e
}

hooked() {
    run_hooked commandline "$@"
}

expect_success() {
    test "$last_status" -eq 0 || fail "expected success: $*"
}

expect_failure() {
    test "$last_status" -ne 0 || fail "expected failure: $*"
}

ran() {
    awk -v prefix="$1" 'index($0, prefix) == 1 { found = 1 } END { exit !found }' "$log" || fail "expected invocation: $1"
}

not_ran() {
    if awk -v prefix="$1" 'index($0, prefix) == 1 { found = 1 } END { exit !found }' "$log"; then
        fail "unexpected invocation: $1"
    fi
}

ran_nothing() {
    test ! -s "$log" || fail "expected no check invocations"
}

ran_before() {
    local first second
    first=$(awk -v prefix="$1" 'index($0, prefix) == 1 { print NR; exit }' "$log")
    second=$(awk -v prefix="$2" 'index($0, prefix) == 1 { print NR; exit }' "$log")
    test -n "$first" && test -n "$second" && test "$first" -lt "$second" || fail "expected '$1' before '$2'"
}

said() {
    grep -qF -- "$1" <<<"$last_output" || fail "expected output: $1"
}

write_files() {
    local path
    for path in "$@"; do
        mkdir -p "$outer/$(dirname "$path")"
        printf '%s\n' "$path" >> "$outer/$path"
    done
}

commit_files() {
    write_files "$@"
    git -C "$outer" add .
    hooked commit --quiet -m "change"
}

plain_commit_files() {
    write_files "$@"
    git -C "$outer" add .
    git -C "$outer" commit --quiet -m "change"
}

expected_nested=0
for configuration in commandline environment; do
    write_files "Sources/Recursion-$configuration.swift"
    git -C "$outer" add .
    run_hooked "$configuration" commit --quiet -m native
    expect_success "native commit with $configuration hooks"
    ran "swift-format lint"
    ran "swiftlint lint"
    not_ran "swift test"
    not_ran "make test-ui-dev-launch"
    said "Skipping unit tests (runs on push)"
    expected_nested=$((expected_nested + 1))
    test "$(git -C "$nested" rev-list --count HEAD)" -eq "$expected_nested" || fail "nested fixture commit count after commit"

    run_hooked "$configuration" push --quiet origin HEAD:main
    expect_success "native push with $configuration hooks"
    ran "swift test"
    ran "make test-ui-dev-launch"
    expected_nested=$((expected_nested + 1))
    test "$(git -C "$nested" rev-list --count HEAD)" -eq "$expected_nested" || fail "nested fixture commit count after push"
done

hooked commit --quiet --allow-empty -m empty
expect_success "empty commit"
said "No changes to check"
ran_nothing

commit_files documentation/guide.md
expect_success "documentation commit"
ran "make no-code-comments"
ran "make no-fixed-width-prose"
not_ran "swift-format"
not_ran "swiftlint"
not_ran "openspec"
not_ran "make docs-check"
said "Skipping format and lint (no native changes)"

hooked push --quiet origin HEAD:main
expect_success "documentation push after a pushed native change"
ran "make no-code-comments"
ran "make docs-check"
ran "fixture-test-release-publishing"
not_ran "swift-format"
not_ran "swift test"
not_ran "make test-ui-dev-launch"
said "Skipping unit tests (no native changes)"

hooked push --quiet origin HEAD:main
expect_success "push with nothing new"
ran_nothing

commit_files screenshots/evidence.png
expect_success "evidence commit"
hooked push --quiet origin HEAD:main
expect_success "evidence push"
ran "make no-code-comments"
not_ran "make docs-check"
not_ran "swift-format"
not_ran "swift test"

commit_files openspec/changes/example/proposal.md
expect_success "OpenSpec commit"
ran "openspec validate --archived"
ran "openspec validate --changes --strict"
ran "openspec validate --specs"
not_ran "swift-format"
hooked push --quiet origin HEAD:main
expect_success "OpenSpec push"
ran "openspec validate --changes --strict"
not_ran "swift test"

commit_files .github/scripts/example.test.mjs
expect_success "CI script commit"
not_ran "node --test"
hooked push --quiet origin HEAD:main
expect_success "CI script push"
ran "node --test"
not_ran "swift test"
not_ran "swift-format"

for allowlisted in README.md Gemfile Gemfile.lock _config.yml _data/example.yml _layouts/example.html assets/example.css favicon.ico CNAME scripts/check-docs.sh scripts/check-docs-taxonomy.rb .agents/skills/example/SKILL.md; do
    plain_commit_files "$allowlisted"
    hooked push --quiet origin HEAD:main
    expect_success "push of allowlisted path $allowlisted"
    not_ran "swift-format"
    not_ran "swift test"
    not_ran "make test-ui-dev-launch"
    said "Skipping unit tests (no native changes)"
done

commit_files .githooks/example
expect_success "hook file commit"
ran "swift-format lint"
hooked push --quiet origin HEAD:main
expect_success "hook file push"
ran "fixture-test-git-hooks"
ran "swift test"
ran_before "fixture-test-git-hooks" "swift test"

commit_files weird-unknown-file.xyz
expect_success "unknown file commit"
ran "swift-format lint"
hooked push --quiet origin HEAD:main
expect_success "unknown file push"
ran "swift test"
ran "make test-ui-dev-launch"

commit_files Sources/Assets/icon.png
expect_success "native image commit"
ran "swift-format lint"
hooked push --quiet origin HEAD:main
expect_success "native image push"
ran "swift test"

write_files Sources/Failing.swift
git -C "$outer" add .
TASK_HOOK_FAIL="swiftlint" hooked commit --quiet -m failing
expect_failure "commit with failing lint"
ran "swift-format lint"
ran "swiftlint lint"
said "format and lint failed"
git -C "$outer" reset --quiet --hard HEAD

plain_commit_files Sources/FailFast.swift
TASK_HOOK_FAIL="swift-format" hooked push --quiet origin HEAD:main
expect_failure "push with failing format"
ran "swift-format lint"
not_ran "swift test"
not_ran "make test-ui-dev-launch"
TASK_HOOK_FAIL="swift test" hooked push --quiet origin HEAD:main
expect_failure "push with failing unit tests"
ran "swift test"
said "unit tests failed"
not_ran "make test-ui-dev-launch"
hooked push --quiet origin HEAD:main
expect_success "push after failures are fixed"
ran_before "swift-format lint" "swift test"
ran_before "swift test" "make test-ui-dev-launch"

plain_commit_files documentation/url-push.md
hooked push --quiet "$remote" HEAD:main
expect_success "push to a remote that is not configured by name"
said "Could not determine the changed files"
ran "swift test"
ran "make test-ui-dev-launch"
git -C "$outer" fetch --quiet origin

hooked push --quiet origin HEAD:refs/heads/scratch
expect_success "push of a new branch whose commits the remote has"
ran_nothing
hooked push --quiet origin :scratch
expect_success "deletion of a remote branch"
ran_nothing
hooked push --quiet origin HEAD:refs/heads/scratch
hooked push --quiet "$remote" :scratch
expect_success "deletion of a remote branch through a URL"
ran_nothing

plain_commit_files Sources/Rewritten.swift
hooked push --quiet origin HEAD:main
expect_success "push before rewrite"
git -C "$outer" commit --quiet --amend -m rewritten
hooked push --quiet --force origin HEAD:main
expect_success "force push of a rewritten commit"
ran "swift test"

for native_path in Package.resolved Makefile project.yml Resources/Info.plist App.entitlements .github/workflows/example.yml Sources/notes.md "Sources/With Space.swift"; do
    plain_commit_files "$native_path"
    hooked push --quiet origin HEAD:main
    expect_success "push of $native_path"
    ran "swift test"
    ran "make test-ui-dev-launch"
done

write_files Sources/PathCommit.swift
git -C "$outer" add .
git -C "$outer" commit --quiet -m "track path commit"
git -C "$outer" push --quiet --no-verify origin HEAD:main
printf 'more\n' >> "$outer/Sources/PathCommit.swift"
hooked commit --quiet -m "commit by path" Sources/PathCommit.swift
expect_success "commit by path"
ran "swift-format lint"
ran "swiftlint lint"
git -C "$outer" push --quiet --no-verify origin HEAD:main

git -C "$outer" mv Sources/PathCommit.swift documentation/moved-from-sources.md
git -C "$outer" add .
hooked commit --quiet -m "move native file into documentation"
expect_success "commit that moves a native file"
ran "swift-format lint"
hooked push --quiet origin HEAD:main
expect_success "push that moves a native file"
ran "swift test"

git -C "$outer" mv documentation/guide.md Sources/guide-moved.md
git -C "$outer" add .
hooked commit --quiet -m "move documentation into native tree"
expect_success "commit that moves documentation into a native directory"
ran "swift-format lint"

git init --quiet --bare "$test_root/other.git"
git -C "$outer" remote add other "$test_root/other.git"
hooked push --quiet origin HEAD:main
expect_success "push of earlier commits before the second remote case"
plain_commit_files documentation/second-remote.md
hooked push --quiet other HEAD:main
expect_success "push to a second remote that has none of the commits"
ran "swift test"
ran "make test-ui-dev-launch"

git -C "$outer" checkout --quiet -b side
plain_commit_files documentation/side-only.md
hooked push --quiet origin side
git -C "$outer" checkout --quiet main
plain_commit_files documentation/main-only.md
hooked push --quiet origin HEAD:main
git -C "$outer" merge --quiet --no-ff --no-commit side >/dev/null 2>&1
write_files Sources/MergeOnly.swift
git -C "$outer" add .
git -C "$outer" commit --quiet --no-verify -m "merge with native change"
hooked push --quiet origin HEAD:main
expect_success "push of a merge commit that adds native code"
ran "swift test"

echo 'Git hook scoping, ordering, fail-fast, push scoping, fixture isolation, and Dev command routing checks passed.'
