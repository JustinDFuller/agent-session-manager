#!/usr/bin/env bash
set -euo pipefail

lsregister="${LSREGISTER_BIN:-/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister}"
osascript_bin="${OSASCRIPT_BIN:-osascript}"
prod_id="com.justinfuller.agent-session-manager"
dev_id="com.justinfuller.agent-session-manager.dev"
if [[ "${1:-}" == "--dev-only" ]]; then
    [[ $# -eq 2 ]] || { printf 'usage: %s --dev-only <dev bundle path>\n' "$0" >&2; exit 2; }
    dev_bundle="$2"
    [[ -d "$dev_bundle" ]] || { printf 'Dev bundle directory does not exist: %s\n' "$dev_bundle" >&2; exit 1; }
    repair_ids=("$dev_id")
    verify_ids=("$dev_id")
    verify_paths=("$dev_bundle")
else
    [[ $# -eq 2 ]] || { printf 'usage: %s <production bundle path> <dev bundle path>\n' "$0" >&2; exit 2; }
    prod_bundle="$1"
    dev_bundle="$2"
    repair_ids=("$prod_id" "$dev_id")
    verify_ids=("$prod_id" "$dev_id")
    verify_paths=("$prod_bundle" "$dev_bundle")
fi
dump="$(mktemp -t agent-session-manager-launch-services.XXXXXX)"
trap 'rm -f "$dump"' EXIT

"$lsregister" -dump > "$dump"

registered_paths() {
    local bundle_id="$1"
    awk -v bundle_id="$bundle_id" '
        /^path:[[:space:]]+/ {
            path = $0
            sub(/^path:[[:space:]]+/, "", path)
            sub(/[[:space:]]+\(0x[[:xdigit:]]+\)$/, "", path)
        }
        /^identifier:[[:space:]]+/ {
            identifier = $0
            sub(/^identifier:[[:space:]]+/, "", identifier)
        }
        /^-+$/ {
            if (identifier == bundle_id && path != "") print path
            path = ""
            identifier = ""
        }
        END {
            if (identifier == bundle_id && path != "") print path
        }
    ' "$dump"
}

for bundle_id in "${repair_ids[@]}"; do
    while IFS= read -r path; do
        [[ -z "$path" ]] || "$lsregister" -u "$path" 2>/dev/null || true
    done < <(registered_paths "$bundle_id")
done

verify_bundle() {
    local bundle_id="$1"
    local bundle_path="$2"
    [[ -d "$bundle_path" ]] || return 0
    "$lsregister" -f "$bundle_path"
    local resolved
    resolved="$(
        "$osascript_bin" -l JavaScript -e \
            "ObjC.import('AppKit'); ObjC.unwrap($.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier('$bundle_id').path)"
    )"
    if [[ "$resolved" != "$bundle_path" ]]; then
        printf 'Launch Services resolved %s to %s, expected %s\n' "$bundle_id" "$resolved" "$bundle_path" >&2
        return 1
    fi
    printf 'Launch Services resolves %s to %s\n' "$bundle_id" "$resolved"
}

for index in "${!verify_ids[@]}"; do
    verify_bundle "${verify_ids[$index]}" "${verify_paths[$index]}"
done
