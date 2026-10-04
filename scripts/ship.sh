#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)

die() {
    echo "INVARIANT VIOLATED: $*" >&2
    exit 1
}

step() {
    echo "==> step: $1"
}

run_xcode_step() {
    local label="$1"; shift
    local logfile="$REPO_ROOT/.build/ship-$label.log"
    mkdir -p "$REPO_ROOT/.build"
    if ! "$@" > "$logfile" 2>&1; then
        echo "--- $label failed; filtered output (full log: $logfile) ---" >&2
        grep -E "error:|warning:|Test Case .*(passed|failed)|Executed .* test|\*\* (BUILD|TEST) (FAILED|SUCCEEDED) \*\*" "$logfile" | tail -60 >&2 || true
        return 1
    fi
    grep -E "Test Suite .*(passed|failed)|Executed .* test|\*\* (BUILD|TEST) SUCCEEDED \*\*" "$logfile" | tail -5 || true
}

COMMIT_MSG_FILE=""
PR_TITLE=""
PR_BODY_FILE=""
SCREENSHOTS_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit-msg-file)
            COMMIT_MSG_FILE="$2"
            shift 2
            ;;
        --pr-title)
            PR_TITLE="$2"
            shift 2
            ;;
        --pr-body-file)
            PR_BODY_FILE="$2"
            shift 2
            ;;
        --screenshots-only)
            SCREENSHOTS_ONLY=true
            shift
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

BRANCH=$(git -C "$REPO_ROOT" branch --show-current)

PORCELAIN=$(git -C "$REPO_ROOT" status --porcelain)
PR_URL=$(gh pr view --json url --jq '.url' 2>/dev/null || echo "")

step "pre-flight"

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    die "pre-flight: branch must not be main or master (current: $BRANCH)"
fi

git -C "$REPO_ROOT" rev-parse HEAD > /dev/null 2>&1 || \
    die "pre-flight: git rev-parse HEAD failed — repository may be corrupted"

gh auth status > /dev/null 2>&1 || \
    die "pre-flight: gh auth status failed — run 'gh auth login'"

run_xcode_step "preflight-build" make -C "$REPO_ROOT" build-for-testing || \
    die "pre-flight: test build failed — sources/UITests do not compile; see .build/ship-preflight-build.log"

if [[ "$SCREENSHOTS_ONLY" == false ]]; then

    if [[ -n "$PORCELAIN" ]]; then
        step "commit"

        [[ -n "$COMMIT_MSG_FILE" ]] || \
            die "commit: working tree is dirty but --commit-msg-file was not provided; clean the tree or pass --commit-msg-file"
        [[ -f "$COMMIT_MSG_FILE" ]] || \
            die "commit: commit message file not found: $COMMIT_MSG_FILE"
        [[ -s "$COMMIT_MSG_FILE" ]] || \
            die "commit: commit message file is empty: $COMMIT_MSG_FILE"

        BEFORE_HEAD=$(git -C "$REPO_ROOT" rev-parse HEAD)
        git -C "$REPO_ROOT" add -A
        git -C "$REPO_ROOT" commit -F "$COMMIT_MSG_FILE"
        AFTER_HEAD=$(git -C "$REPO_ROOT" rev-parse HEAD)

        [[ "$AFTER_HEAD" != "$BEFORE_HEAD" ]] || \
            die "commit: HEAD did not advance after commit"
    fi

    step "push"

    git -C "$REPO_ROOT" push -u origin "$BRANCH" || \
        die "push: 'git push -u origin $BRANCH' failed — never use --force"

    UPSTREAM=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")
    [[ -n "$UPSTREAM" ]] || \
        die "push: upstream tracking branch not set after push"

    step "ensure-pr"

    if [[ -z "$PR_URL" ]]; then
        [[ -n "$PR_TITLE" ]] || \
            die "ensure-pr: no PR exists for this branch and --pr-title was not provided"
        [[ -n "$PR_BODY_FILE" ]] || \
            die "ensure-pr: no PR exists for this branch and --pr-body-file was not provided"
        [[ -f "$PR_BODY_FILE" ]] || \
            die "ensure-pr: PR body file not found: $PR_BODY_FILE"

        gh pr create --draft --title "$PR_TITLE" --body-file "$PR_BODY_FILE"

        PR_URL=$(gh pr view --json url --jq '.url' 2>/dev/null || echo "")
        [[ -n "$PR_URL" ]] || \
            die "ensure-pr: PR creation appeared to succeed but no PR URL found"
    fi

fi

if [[ "$SCREENSHOTS_ONLY" == true ]]; then
    [[ -n "$PR_URL" ]] || \
        die "ensure-pr: no PR found for branch '$BRANCH' — run without --screenshots-only to create one"
fi

step "build-screenshots"

EXPECTED_NAMES=()
while IFS= read -r name; do
    [[ -n "$name" ]] && EXPECTED_NAMES+=("$name.png")
done < <(grep -hoE 'screenshot\("[^"]+"' "$REPO_ROOT"/UITests/Screenshot*.swift "$REPO_ROOT"/UITests/ClaudeNotificationFlowTests.swift | \
         sed 's/screenshot("//;s/"$//' | sort -u)

[[ ${#EXPECTED_NAMES[@]} -gt 0 ]] || \
    die "build-screenshots: no screenshot(...) calls found in the screenshot test classes"

run_xcode_step "screenshots" make -C "$REPO_ROOT" screenshots || \
    die "build-screenshots: xcodebuild failed; see .build/ship-screenshots.log"

ACTUAL_NAMES=()
while IFS= read -r f; do
    [[ -n "$f" ]] && ACTUAL_NAMES+=("$(basename "$f")")
done < <(find "$REPO_ROOT/screenshots/" -maxdepth 1 -name "*.png" 2>/dev/null | sort)

MISSING=()
for expected in "${EXPECTED_NAMES[@]}"; do
    found=false
    for actual in "${ACTUAL_NAMES[@]}"; do
        [[ "$actual" == "$expected" ]] && found=true && break
    done
    [[ "$found" == true ]] || MISSING+=("$expected")
done

EXTRA=()
for actual in "${ACTUAL_NAMES[@]}"; do
    found=false
    for expected in "${EXPECTED_NAMES[@]}"; do
        [[ "$actual" == "$expected" ]] && found=true && break
    done
    [[ "$found" == true ]] || EXTRA+=("$actual")
done

if [[ ${#MISSING[@]} -gt 0 || ${#EXTRA[@]} -gt 0 ]]; then
    msg="build-screenshots: screenshot set mismatch"
    [[ ${#MISSING[@]} -gt 0 ]] && msg+="; missing: ${MISSING[*]}"
    [[ ${#EXTRA[@]} -gt 0 ]] && msg+="; extra: ${EXTRA[*]}"
    die "$msg"
fi

step "upload-screenshots"

GIST_ID=$(bash "$SCRIPT_DIR/upload-screenshots.sh" | tail -1)
[[ -n "$GIST_ID" ]] || \
    die "upload-screenshots: upload script did not print a gist ID"

BASE_URL="https://gist.githubusercontent.com/JustinDFuller/${GIST_ID}/raw"

FIRST_PNG="${EXPECTED_NAMES[0]}"
HTTP_STATUS=$(curl -sfI "$BASE_URL/$FIRST_PNG" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
[[ "$HTTP_STATUS" == "200" ]] || \
    die "upload-screenshots: spot-check of $FIRST_PNG returned HTTP $HTTP_STATUS (expected 200)"

step "update-pr-body"

EXAMPLE_SECTION=$(bash "$SCRIPT_DIR/lib/render-example-section.sh" "$REPO_ROOT/screenshots" "$BASE_URL")

CURRENT_BODY=$(gh pr view --json body --jq '.body')

if echo "$CURRENT_BODY" | grep -q "^## Example"; then
    PREFIX=$(echo "$CURRENT_BODY" | sed '/^## Example/,$d')
else
    PREFIX="$CURRENT_BODY"
fi

NEW_BODY="${PREFIX}${EXAMPLE_SECTION}"
gh pr edit --body "$NEW_BODY"

REFETCHED_BODY=$(gh pr view --json body --jq '.body')
MISSING_FROM_BODY=()
for name in "${EXPECTED_NAMES[@]}"; do
    echo "$REFETCHED_BODY" | grep -q "$name" || MISSING_FROM_BODY+=("$name")
done

if [[ ${#MISSING_FROM_BODY[@]} -gt 0 ]]; then
    die "update-pr-body: the following PNGs are missing from the updated PR body: ${MISSING_FROM_BODY[*]}"
fi

step "done"
echo "PR: $PR_URL"
