#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d -t agent-session-manager-launch-services-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

assert_log_contains() {
    local log_file="$1"
    local expected="$2"
    grep -Fqx -- "$expected" "$log_file" || fail "Expected operation missing from $log_file: $expected"
}

assert_log_excludes() {
    local log_file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$log_file"; then
        fail "Unexpected operation found in $log_file: $unexpected"
    fi
}

assert_log_excludes_exact() {
    local log_file="$1"
    local unexpected="$2"
    if grep -Fqx -- "$unexpected" "$log_file"; then
        fail "Unexpected operation found in $log_file: $unexpected"
    fi
}

mkdir -p "$test_root/production.app" "$test_root/dev.app" "$test_root/old-production.app" "$test_root/old-dev.app"
production_bundle="$test_root/production.app"
dev_bundle="$test_root/dev.app"
old_production_bundle="$test_root/old-production.app"
old_dev_bundle="$test_root/old-dev.app"
production_id="com.justinfuller.agent-session-manager"
dev_id="com.justinfuller.agent-session-manager.dev"

cat > "$test_root/lsregister" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LSREGISTER_LOG"
case "$1" in
    -dump) cat "$LSREGISTER_DUMP" ;;
    -u|-f) ;;
    *) exit 2 ;;
esac
SH

cat > "$test_root/osascript" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
expression="$*"
bundle_id="$(printf '%s' "$expression" | sed -n "s/.*BundleIdentifier('\\([^']*\\)').*/\\1/p")"
printf '%s\n' "$bundle_id" >> "$RESOLVER_LOG"
resolved="$(awk -F '\t' -v bundle_id="$bundle_id" '$1 == bundle_id { print substr($0, index($0, "\t") + 1); exit }' "$RESOLVER_MAP")"
[[ -n "$resolved" ]] || exit 2
printf '%s\n' "$resolved"
SH

chmod +x "$test_root/lsregister" "$test_root/osascript"
printf 'path: %s (0x100)\nidentifier: %s\n--------------------\npath: %s (0x101)\nidentifier: %s\n--------------------\n' \
    "$old_production_bundle" "$production_id" "$old_dev_bundle" "$dev_id" > "$test_root/dump"
printf '%s\t%s\n%s\t%s\n' "$production_id" "$production_bundle" "$dev_id" "$dev_bundle" > "$test_root/resolver-map"

run_repair() {
    LSREGISTER_BIN="$test_root/lsregister" \
        OSASCRIPT_BIN="$test_root/osascript" \
        LSREGISTER_DUMP="$test_root/dump" \
        LSREGISTER_LOG="$test_root/lsregister.log" \
        RESOLVER_MAP="$test_root/resolver-map" \
        RESOLVER_LOG="$test_root/resolver.log" \
        make --no-print-directory -C "$repo_root" "$@"
}

: > "$test_root/lsregister.log"
: > "$test_root/resolver.log"
run_repair repair-launch-services-dev APP_BUNDLE_DEV="$dev_bundle"
assert_log_contains "$test_root/lsregister.log" "-u $old_dev_bundle"
assert_log_contains "$test_root/lsregister.log" "-f $dev_bundle"
assert_log_excludes "$test_root/lsregister.log" "$old_production_bundle"
assert_log_excludes "$test_root/lsregister.log" "$production_bundle"
assert_log_contains "$test_root/resolver.log" "$dev_id"
assert_log_excludes_exact "$test_root/resolver.log" "$production_id"

: > "$test_root/lsregister.log"
: > "$test_root/resolver.log"
if run_repair repair-launch-services-dev APP_BUNDLE_DEV="$test_root/missing-dev.app" > "$test_root/missing.out" 2> "$test_root/missing.err"; then
    fail 'Dev-only repair succeeded when the requested Dev bundle was missing'
fi
grep -Fq 'Dev bundle directory does not exist:' "$test_root/missing.err" || fail 'Missing Dev bundle was not reported'
[[ ! -s "$test_root/lsregister.log" ]] || fail 'Missing Dev bundle caused Launch Services calls'
[[ ! -s "$test_root/resolver.log" ]] || fail 'Missing Dev bundle caused resolver calls'

: > "$test_root/lsregister.log"
: > "$test_root/resolver.log"
printf '%s\t%s\n' "$dev_id" "$test_root/wrong-dev.app" > "$test_root/resolver-map"
if run_repair repair-launch-services-dev APP_BUNDLE_DEV="$dev_bundle" > "$test_root/mismatch.out" 2> "$test_root/mismatch.err"; then
    fail 'Dev-only repair succeeded when Launch Services resolved to the wrong bundle'
fi
grep -Fq "Launch Services resolved $dev_id" "$test_root/mismatch.err" || fail 'Dev-only resolver mismatch was not reported'
assert_log_excludes "$test_root/lsregister.log" "$old_production_bundle"
assert_log_excludes_exact "$test_root/resolver.log" "$production_id"

: > "$test_root/lsregister.log"
: > "$test_root/resolver.log"
printf '%s\t%s\n%s\t%s\n' "$production_id" "$production_bundle" "$dev_id" "$dev_bundle" > "$test_root/resolver-map"
run_repair repair-launch-services APP_BUNDLE="$production_bundle" APP_BUNDLE_DEV="$dev_bundle"
assert_log_contains "$test_root/lsregister.log" "-u $old_production_bundle"
assert_log_contains "$test_root/lsregister.log" "-u $old_dev_bundle"
assert_log_contains "$test_root/lsregister.log" "-f $production_bundle"
assert_log_contains "$test_root/lsregister.log" "-f $dev_bundle"
assert_log_contains "$test_root/resolver.log" "$production_id"
assert_log_contains "$test_root/resolver.log" "$dev_id"

dev_recipe="$(sed -n '/^app-dev:/,/^run-dev:/p' "$repo_root/Makefile")"
printf '%s\n' "$dev_recipe" | grep -Fq -- '$(MAKE) repair-launch-services-dev' || fail 'app-dev does not use the Dev-only repair target'
printf '%s\n' "$dev_recipe" | grep -Fq -- '--platform macosx --minimum-deployment-target 26.0' || fail 'app-dev no longer builds with the macOS 26 deployment floor'

printf '%s\n' 'Launch Services repair scope tests passed.'
