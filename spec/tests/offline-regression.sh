#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/spec/fixtures"
RULES_FILE="$ROOT_DIR/skills/smart-web-fetch/assets/fetch-rules.json"
CONTRACT_FILE="$ROOT_DIR/spec/fetch-contract.md"

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

assert_file_exists() {
    local path="$1"
    [[ -f "$path" ]] || fail "Missing required file: $path"
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    if ! grep -qi -- "$pattern" "$path"; then
        fail "Expected pattern '$pattern' in $path"
    fi
}

main() {
    assert_file_exists "$CONTRACT_FILE"
    assert_file_exists "$RULES_FILE"
    assert_file_exists "$FIXTURE_DIR/markdown-success.json"
    assert_file_exists "$FIXTURE_DIR/structured-error.json"
    assert_file_exists "$FIXTURE_DIR/html-error-page.html"
    assert_file_exists "$FIXTURE_DIR/too-short.txt"

    # HTML fixture should stay aligned with contract keywords.
    assert_file_contains "$FIXTURE_DIR/html-error-page.html" "<html"
    assert_file_contains "$FIXTURE_DIR/html-error-page.html" "<title"
    assert_file_contains "$FIXTURE_DIR/html-error-page.html" "forbidden"
    assert_file_contains "$FIXTURE_DIR/html-error-page.html" "access denied"

    # Keep the "too-short" fixture truly short for threshold checks.
    local too_short_len
    too_short_len=$(wc -c < "$FIXTURE_DIR/too-short.txt")
    [[ "$too_short_len" -lt 40 ]] || fail "Expected too-short fixture length < 40, got $too_short_len"

    # JSON fixture sanity checks via Python stdlib only.
    python3 - "$FIXTURE_DIR/markdown-success.json" "$FIXTURE_DIR/structured-error.json" "$RULES_FILE" <<'PY'
import json
import sys

markdown_fixture, error_fixture, rules_file = sys.argv[1:]

with open(markdown_fixture, "r", encoding="utf-8") as f:
    markdown_data = json.load(f)
markdown_value = str(markdown_data.get("markdown", ""))
if len(markdown_value) < 40:
    raise SystemExit("markdown-success.json markdown field should be >= 40 chars")

with open(error_fixture, "r", encoding="utf-8") as f:
    error_data = json.load(f)
if error_data.get("error") is not True:
    raise SystemExit("structured-error.json must have error=true")
if "forbidden" not in str(error_data.get("message", "")).lower():
    raise SystemExit("structured-error.json message should include forbidden")

with open(rules_file, "r", encoding="utf-8") as f:
    rules = json.load(f)
thresholds = rules.get("thresholds", {})
for key in ("jina", "markdown_new", "defuddle", "basic"):
    value = thresholds.get(key)
    if not isinstance(value, int) or value <= 0:
        raise SystemExit(f"rules threshold '{key}' must be a positive integer")
PY

    # Basic script syntax checks.
    bash -n "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch"
    bash -n "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch-core"

    echo "[PASS] Offline regression checks passed"
}

main "$@"
