#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/smart-web-fetch"
FIXTURE_DIR="$ROOT_DIR/spec/fixtures"
RULES_FILE="$ROOT_DIR/skills/smart-web-fetch/assets/fetch-rules.json"
CONTRACT_FILE="$ROOT_DIR/spec/fetch-contract.md"
PYTHON_CORE_DIR="$SKILL_DIR/core"
PYTHON_MAIN="$SKILL_DIR/main.py"
UNSUPPORTED_PYTHON_MAIN="$PYTHON_CORE_DIR/__main__.py"
PYTHON_BIN=""
PYTHON_VERSION_CHECK='import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'
LEGACY_CORE_PATTERN='smart_web_fetch_core'

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

assert_file_exists() {
    local path="$1"
    [[ -f "$path" ]] || fail "Missing required file: $path"
}

assert_file_not_exists() {
    local path="$1"
    [[ ! -e "$path" ]] || fail "Expected file to be removed: $path"
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    if ! grep -qi -- "$pattern" "$path"; then
        fail "Expected pattern '$pattern' in $path"
    fi
}

assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    if grep -qi -- "$pattern" "$path"; then
        fail "Unexpected pattern '$pattern' in $path"
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

assert_json_boolean_false() {
    local path="$1"
    local field="$2"
    if ! grep -Eq "\"$field\"[[:space:]]*:[[:space:]]*false" "$path"; then
        fail "Expected $field=false in $path"
    fi
}

assert_json_string_equals() {
    local path="$1"
    local field="$2"
    local expected="$3"
    local actual

    actual=$(extract_json_string_field "$path" "$field") || fail "Expected string field $field in $path"
    [[ "$actual" == "$expected" ]] || fail "Expected $field=$expected in $path, got $actual"
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

find_python() {
    local candidate
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "$PYTHON_VERSION_CHECK" >/dev/null 2>&1; then
            PYTHON_BIN="$candidate"
            return 0
        fi
    done
    fail "Python 3.11+ is required for offline regression"
}

main() {
    find_python

    assert_file_exists "$CONTRACT_FILE"
    assert_file_exists "$RULES_FILE"
    assert_file_exists "$PYTHON_MAIN"
    assert_file_not_exists "$UNSUPPORTED_PYTHON_MAIN"
    assert_file_exists "$FIXTURE_DIR/markdown-success.json"
    assert_file_exists "$FIXTURE_DIR/structured-error.json"
    assert_file_exists "$FIXTURE_DIR/html-error-page.html"
    assert_file_exists "$FIXTURE_DIR/too-short.txt"
    assert_file_not_exists "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch-core"
    assert_file_not_exists "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch-core.ps1"
    assert_file_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch" "main.py"
    assert_file_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.ps1" "main.py"
    assert_file_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.cmd" "main.py"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch" "-m core"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.ps1" "-m core"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.cmd" "-m core"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch" "$LEGACY_CORE_PATTERN"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.ps1" "$LEGACY_CORE_PATTERN"
    assert_file_not_contains "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch.cmd" "$LEGACY_CORE_PATTERN"
    assert_file_not_contains "$ROOT_DIR/README.md" "python -m core"
    assert_file_not_contains "$ROOT_DIR/README_EN.md" "python -m core"
    assert_file_not_contains "$ROOT_DIR/spec/fetch-contract.md" "python -m core"
    assert_file_not_contains "$ROOT_DIR/spec/wrapper-runtime.md" "python -m core"
    assert_file_not_contains "$SKILL_DIR/SKILL.md" "python -m core"

    if rg -n --glob '!**/__pycache__/**' "$LEGACY_CORE_PATTERN" \
        "$ROOT_DIR/README.md" \
        "$ROOT_DIR/README_EN.md" \
        "$ROOT_DIR/spec/fetch-contract.md" \
        "$ROOT_DIR/spec/wrapper-runtime.md" \
        "$ROOT_DIR/spec/tests/json-smoke.sh" \
        "$ROOT_DIR/spec/tests/json-smoke.ps1" \
        "$ROOT_DIR/spec/tests/json-smoke-server.py" \
        "$SKILL_DIR/SKILL.md" \
        "$SKILL_DIR/scripts" \
        "$PYTHON_CORE_DIR" >/dev/null; then
        fail "Found stale references to the legacy Python package name"
    fi

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

    # Structured CLI JSON contract sanity checks.
    local cli_success_json cli_failure_json
    cli_success_json=$(mktemp)
    cli_failure_json=$(mktemp)

    printf '%s\n' '{"success":true,"url":"https://example.com","content":"line 1\nline 2","source":"jina"}' > "$cli_success_json"
    printf '%s\n' '{"success":false,"url":"https://example.com","content":"","source":"none","error":"request failed"}' > "$cli_failure_json"

    assert_json_boolean_true "$cli_success_json" "success"
    assert_json_string_equals "$cli_success_json" "source" "jina"
    extract_json_string_field "$cli_success_json" "content" >/dev/null || fail "Expected content field in success JSON"

    assert_json_boolean_false "$cli_failure_json" "success"
    assert_json_string_equals "$cli_failure_json" "source" "none"
    extract_json_string_field "$cli_failure_json" "error" >/dev/null || fail "Expected error field in failure JSON"
    rm -f "$cli_success_json" "$cli_failure_json"

    # Basic script syntax checks.
    assert_bash_syntax "$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch"
    "$PYTHON_BIN" -m compileall -q "$SKILL_DIR" || fail "Python syntax check failed: $SKILL_DIR"

    "$PYTHON_BIN" - "$SKILL_DIR" <<'PY'
import pathlib
import sys

skill_dir = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(skill_dir))

import core as module
import core.sources as sources

rules = module.load_rules(False)
assert module.normalize_url("example.com") == "https://example.com"
assert module.normalize_url("localhost:3000/foo") == "https://localhost:3000/foo"
assert module.normalize_url("example.com:8080/path") == "https://example.com:8080/path"
assert module.normalize_url("http://example.com") == "http://example.com"
assert module.normalize_url("HTTPS://Example.com/demo?q=1") == "https://Example.com/demo?q=1"
try:
    module.normalize_url("ftp://example.com")
except module.CLIError as exc:
    assert "Unsupported URL scheme" in str(exc)
else:
    raise AssertionError("Expected ftp:// URL to fail validation")
try:
    module.normalize_url("[::1]extra")
except module.CLIError as exc:
    assert "Invalid URL:" in str(exc)
else:
    raise AssertionError("Expected malformed IPv6 URL to fail validation")
assert rules.jina_min_length >= 100
assert module.is_structured_error_response('{"error":true,"message":"forbidden"}', rules) is True
assert module.is_likely_html_error_payload(
    "<html><title>Access denied</title><body>forbidden</body></html>",
    "text/html; charset=utf-8",
    rules,
) is True
markdown, is_json = module.extract_markdown_field('{"markdown":"hello world"}')
assert is_json is True
assert markdown == "hello world"
assert module.is_binary_response("image/png", b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR") is True
assert module.is_binary_response("application/octet-stream", b"abc") is True
assert module.is_binary_response("text/plain; charset=utf-8", "你好，world".encode("utf-8")) is False
assert module.is_binary_response("text/plain; charset=utf-16", b"\xff\xfeH\x00i\x00") is False
payload = module.render_payload(True, "https://example.com", "body", "jina")
assert payload == '{"success":true,"url":"https://example.com","content":"body","source":"jina"}'
decoded_utf16 = module.decode_response_body(b"\xff\xfeH\x00i\x00", {})
assert decoded_utf16 == "Hi"
decoded_latin1 = module.decode_response_body("caf\xe9".encode("latin-1"), {})
assert decoded_latin1 == "café"
class InvalidCharsetHeaders:
    @staticmethod
    def get_content_charset():
        return "not-a-real-charset"


decoded_invalid_charset = module.decode_response_body("caf\xe9".encode("latin-1"), InvalidCharsetHeaders())
assert decoded_invalid_charset == "café"
short_json = '{"markdown":"tiny","meta":"' + ("x" * 200) + '"}'
sources.request_text = lambda *args, **kwargs: module.ResponseData(
    status_code=200,
    content_type="application/json",
    raw_body=short_json.encode("utf-8"),
    text=short_json,
)
try:
    module.fetch_markdown_new("https://example.com", rules, False)
except module.CLIError as exc:
    assert exc.source == "markdown"
    assert "too-short" in str(exc)
else:
    raise AssertionError("Expected markdown.new extracted content length validation to fail")
try:
    module.fetch_defuddle("https://example.com", rules, False)
except module.CLIError as exc:
    assert exc.source == "defuddle"
    assert "too-short" in str(exc)
else:
    raise AssertionError("Expected defuddle extracted content length validation to fail")
html = "<html><body><script>{}</script><p>tiny</p></body></html>".format("x" * 200)
sources.request_text = lambda *args, **kwargs: module.ResponseData(
    status_code=200,
    content_type="text/html; charset=utf-8",
    raw_body=html.encode("utf-8"),
    text=html,
)
try:
    module.fetch_basic(
        "https://example.com",
        module.Rules(
            jina_min_length=100,
            markdown_min_length=40,
            defuddle_min_length=40,
            basic_min_length=50,
            structured_error_keywords=[],
            html_error_keywords=[],
        ),
        False,
        False,
    )
except module.CLIError as exc:
    assert exc.source == "basic"
    assert "after HTML cleanup" in str(exc)
else:
    raise AssertionError("Expected cleaned HTML length validation to fail")
PY

    echo "[PASS] Offline regression checks passed"
}

main "$@"
