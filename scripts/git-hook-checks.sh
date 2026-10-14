#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
remote_name=${2:-}

if [[ "$mode" != pre-commit && "$mode" != pre-push ]]; then
    echo "usage: git-hook-checks.sh pre-commit | pre-push <remote> [<url>]" >&2
    exit 2
fi

paths_file=$(mktemp)
trap 'rm -f "$paths_file"' EXIT

undetermined=0
any=0
openspec=0
docs=0
ci_scripts=0
hooks=0
native=0

collect_staged() {
    git diff --cached --name-only --no-renames -z >"$paths_file" || undetermined=1
}

collect_pushed() {
    local local_ref local_sha remote_ref remote_sha remote_checked=0
    while read -r local_ref local_sha remote_ref remote_sha; do
        case "$local_sha" in
            *[!0]*) ;;
            *) continue ;;
        esac
        if [[ "$remote_checked" == 0 ]]; then
            if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
                undetermined=1
                return
            fi
            remote_checked=1
        fi
        git log -m --no-renames --name-only --format= -z "$local_sha" --not "--remotes=$remote_name" >>"$paths_file" || undetermined=1
    done
}

classify_path() {
    case "$1" in
        openspec/*)
            openspec=1
            ;;
        documentation/* | _data/* | _layouts/* | assets/* | _config.yml | Gemfile | Gemfile.lock | favicon.ico | CNAME | scripts/check-docs.sh | scripts/check-docs-taxonomy.rb | scripts/test-release-publishing.sh)
            docs=1
            ;;
        screenshots/* | .claude/skills/* | .agents/skills/*) ;;
        .github/scripts/*)
            ci_scripts=1
            ;;
        .githooks/* | scripts/git-hook-checks.sh | scripts/test-git-hooks.sh)
            hooks=1
            native=1
            ;;
        */*)
            native=1
            ;;
        *.md)
            docs=1
            ;;
        *)
            native=1
            ;;
    esac
}

if [[ "$mode" == pre-commit ]]; then
    collect_staged
else
    collect_pushed
fi

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    any=1
    classify_path "$path"
done <"$paths_file"

if [[ "$undetermined" == 1 ]]; then
    echo "==> Could not determine the changed files; running every native check."
    any=1
    native=1
fi

if [[ "$any" == 0 ]]; then
    echo "==> No changes to check."
    exit 0
fi

groups=""
for group in openspec docs ci_scripts hooks native; do
    if [[ "${!group}" == 1 ]]; then
        groups="${groups:+$groups, }${group//_/-}"
    fi
done
echo "==> Changed file groups: ${groups:-other non-native files}"

tier() {
    local label=$1 applies=$2 reason=$3 stage=$4
    shift 4
    if [[ "$applies" != 1 ]]; then
        echo "==> Skipping $label ($reason)"
        return 0
    fi
    if [[ "$stage" == push && "$mode" != pre-push ]]; then
        echo "==> Skipping $label (runs on push)"
        return 0
    fi
    echo "==> Running $label..."
    if ! "$@"; then
        echo "==> $label failed" >&2
        exit 1
    fi
}

check_comments_and_prose() {
    make no-code-comments || return 1
    make no-fixed-width-prose || return 1
}

check_openspec() {
    openspec validate --archived --no-interactive || return 1
    openspec validate --changes --strict --no-interactive || return 1
    openspec validate --specs --no-interactive || return 1
}

check_format_and_lint() {
    swift-format lint --recursive --strict Sources/ Tests/ UITests/ || return 1
    swiftlint lint --strict --config .swiftlint.yml || return 1
}

check_ci_scripts() {
    node --test .github/scripts/*.test.mjs
}

check_hooks() {
    bash scripts/test-git-hooks.sh
}

check_docs() {
    make docs-check || return 1
    scripts/test-release-publishing.sh || return 1
}

check_unit_tests() {
    local output
    output=$(mktemp)
    if ! swift test >"$output" 2>&1; then
        grep -E "(error:|FAILED|Test.*failed|\.swift:[0-9])" "$output" || cat "$output"
        rm -f "$output"
        return 1
    fi
    grep -E "Test Suite 'All tests'" "$output" | tail -1 || echo "Tests passed."
    rm -f "$output"
}

check_ui_smoke() {
    make test-ui-dev-launch
}

tier "comment and prose checks" "$any" "no changes" commit check_comments_and_prose
tier "OpenSpec validation" "$openspec" "no OpenSpec changes" commit check_openspec
tier "format and lint" "$native" "no native changes" commit check_format_and_lint
tier "CI script tests" "$ci_scripts" "no CI script changes" push check_ci_scripts
tier "hook tests" "$hooks" "no hook changes" push check_hooks
tier "documentation build" "$docs" "no documentation changes" push check_docs
tier "unit tests" "$native" "no native changes" push check_unit_tests
tier "UI smoke tests" "$native" "no native changes" push check_ui_smoke

echo "==> All applicable checks passed."
