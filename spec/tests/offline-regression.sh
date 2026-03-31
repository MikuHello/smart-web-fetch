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

extract_json_string_field() {
    local path="$1"
    local field="$2"
    awk -v target="$field" '
        {
            text = text $0 "\n"
        }
        END {
            pattern = "\"" target "\"[[:space:]]*:[[:space:]]*\""
            if (!match(text, pattern)) {
                exit 1
            }

            pos = RSTART + RLENGTH
            value = ""
            n = length(text)

            while (pos <= n) {
                ch = substr(text, pos, 1)
                if (ch == "\\") {
                    pos++
                    if (pos > n) {
                        exit 1
                    }

                    esc = substr(text, pos, 1)
                    if (esc == "u") {
                        hex = substr(text, pos + 1, 4)
                        if (hex !~ /^[0-9A-Fa-f]{4}$/) {
                            exit 1
                        }
                        value = value "?"
                        pos += 4
                    } else {
                        value = value esc
                    }
                } else if (ch == "\"") {
                    print value
                    exit 0
                } else {
                    value = value ch
                }

                pos++
            }

            exit 1
        }
    ' "$path"
}

extract_json_object_segment() {
    local path="$1"
    local field="$2"
    awk -v target="$field" '
        {
            text = text $0 "\n"
        }
        END {
            pattern = "\"" target "\"[[:space:]]*:[[:space:]]*\\{"
            if (!match(text, pattern)) {
                exit 1
            }

            start = RSTART + RLENGTH - 1
            n = length(text)
            depth = 0
            in_string = 0
            escaped = 0

            for (pos = start; pos <= n; pos++) {
                ch = substr(text, pos, 1)

                if (in_string) {
                    if (escaped) {
                        escaped = 0
                    } else if (ch == "\\") {
                        escaped = 1
                    } else if (ch == "\"") {
                        in_string = 0
                    }
                } else {
                    if (ch == "\"") {
                        in_string = 1
                    } else if (ch == "{") {
                        depth++
                    } else if (ch == "}") {
                        depth--
                        if (depth == 0) {
                            print substr(text, start, pos - start + 1)
                            exit 0
                        }
                    }
                }
            }

            exit 1
        }
    ' "$path"
}

assert_json_boolean_true() {
    local path="$1"
    local field="$2"
    if ! grep -Eq "\"$field\"[[:space:]]*:[[:space:]]*true" "$path"; then
        fail "Expected $field=true in $path"
    fi
}

assert_positive_integer_threshold_field() {
    local path="$1"
    local field="$2"
    local segment

    segment=$(extract_json_object_segment "$path" "thresholds") || fail "Expected thresholds object in $path"
    if ! printf '%s\n' "$segment" | grep -Eq "\"$field\"[[:space:]]*:[[:space:]]*[1-9][0-9]*"; then
        fail "Expected positive integer thresholds.$field in $path"
    fi
}

assert_bash_syntax() {
    local path="$1"
    if ! tr -d '\r' < "$path" | bash -n; then
        fail "Bash syntax check failed: $path"
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
    assert_file_contains "$FIXTURE_DIR/html-error-page.html" "access denied"

    # Keep the "too-short" fixture truly short for threshold checks.
    local too_short_len
    too_short_len=$(wc -c < "$FIXTURE_DIR/too-short.txt")
    [[ "$too_short_len" -lt 40 ]] || fail "Expected too-short fixture length < 40, got $too_short_len"

    # JSON fixture sanity checks without requiring Python.
    local markdown_value
    markdown_value=$(extract_json_string_field "$FIXTURE_DIR/markdown-success.json" "markdown")
    [[ -n "$markdown_value" ]] || fail "markdown-success.json must include a markdown field"
    [[ ${#markdown_value} -ge 40 ]] || fail "markdown-success.json markdown field should be >= 40 chars"

    assert_json_boolean_true "$FIXTURE_DIR/structured-error.json" "error"
    assert_file_contains "$FIXTURE_DIR/structured-error.json" "forbidden"

    assert_positive_integer_threshold_field "$RULES_FILE" "jina"
    assert_positive_integer_threshold_field "$RULES_FILE" "markdown_new"
    assert_positive_integer_threshold_field "$RULES_FILE" "defuddle"
    assert_positive_integer_threshold_field "$RULES_FILE" "basic"

    # Basic script syntax checks.
    assert_bash_syntax "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch"
    assert_bash_syntax "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch-core"

    echo "[PASS] Offline regression checks passed"
}

main "$@"
