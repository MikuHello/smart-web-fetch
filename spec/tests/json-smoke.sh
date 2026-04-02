#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/skills/smart-web-fetch/scripts/smart-web-fetch"
SERVER_SCRIPT="$ROOT_DIR/spec/tests/json-smoke-server.py"
PORT="${SMART_WEB_FETCH_TEST_PORT:-18765}"
SERVER_PID=""
PYTHON_BIN=""
PYTHON_VERSION_CHECK='import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

wait_for_server() {
    local attempt
    for attempt in $(seq 1 30); do
        if "$PYTHON_BIN" - "$PORT" <<'PY'
import socket
import sys

sock = socket.socket()
sock.settimeout(0.2)
try:
    sock.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
        then
            return 0
        fi
        sleep 0.2
    done

    fail "Smoke test server did not start on port $PORT"
}

assert_json_success() {
    local path="$1"
    local expected_source="$2"

    "$PYTHON_BIN" - "$path" "$expected_source" <<'PY'
import json
import sys

path = sys.argv[1]
expected_source = sys.argv[2]
with open(path, encoding="utf-8") as fh:
    payload = json.load(fh)

assert payload["success"] is True, payload
assert isinstance(payload["content"], str), payload
assert payload["source"] == expected_source, payload
assert isinstance(payload["url"], str) and payload["url"], payload
PY
}

assert_json_url_equals() {
    local path="$1"
    local expected_url="$2"

    "$PYTHON_BIN" - "$path" "$expected_url" <<'PY'
import json
import sys

path = sys.argv[1]
expected_url = sys.argv[2]
with open(path, encoding="utf-8") as fh:
    payload = json.load(fh)

assert payload["url"] == expected_url, payload
PY
}

assert_json_failure() {
    local path="$1"
    local expected_source="$2"

    "$PYTHON_BIN" - "$path" "$expected_source" <<'PY'
import json
import sys

path = sys.argv[1]
expected_source = sys.argv[2]
with open(path, encoding="utf-8") as fh:
    payload = json.load(fh)

assert payload["success"] is False, payload
assert payload["source"] == expected_source, payload
assert payload["content"] == "", payload
assert isinstance(payload.get("error"), str) and payload["error"], payload
PY
}

assert_json_error_contains() {
    local path="$1"
    local expected_fragment="$2"

    "$PYTHON_BIN" - "$path" "$expected_fragment" <<'PY'
import json
import sys

path = sys.argv[1]
expected_fragment = sys.argv[2]
with open(path, encoding="utf-8") as fh:
    payload = json.load(fh)

assert expected_fragment in payload.get("error", ""), payload
PY
}

assert_file_not_contains() {
    local path="$1"
    local unexpected_fragment="$2"
    if grep -q -- "$unexpected_fragment" "$path"; then
        fail "Unexpected '$unexpected_fragment' in $path"
    fi
}

assert_file_contains() {
    local path="$1"
    local expected_fragment="$2"
    if ! grep -q -- "$expected_fragment" "$path"; then
        fail "Expected '$expected_fragment' in $path"
    fi
}

assert_help_output() {
    local path="$1"
    assert_file_contains "$path" "Smart Web Fetch"
    assert_file_not_contains "$path" "FAKE_CORE_SHADOWED"
}

trap cleanup EXIT

for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "$PYTHON_VERSION_CHECK" >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"
        break
    fi
done

[[ -n "$PYTHON_BIN" ]] || fail "Python 3.11+ is required for json-smoke.sh"

"$PYTHON_BIN" "$SERVER_SCRIPT" --port "$PORT" &
SERVER_PID=$!
wait_for_server

bash "$SCRIPT_PATH" --help >/dev/null || fail "--help should succeed"

shadow_dir="$(mktemp -d)"
shadow_stdout="$(mktemp)"
shadow_stderr="$(mktemp)"
printf '%s\n' 'print("FAKE_CORE_SHADOWED")' > "$shadow_dir/core.py"
(
    cd "$shadow_dir"
    bash "$SCRIPT_PATH" --help >"$shadow_stdout" 2>"$shadow_stderr"
) || fail "shadowed core.py should not break Bash wrapper help"
assert_help_output "$shadow_stdout"
assert_file_not_contains "$shadow_stderr" "FAKE_CORE_SHADOWED"
rm -rf "$shadow_dir"

success_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-success" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com --json >"$success_json"
assert_json_success "$success_json" "jina"

forced_jina_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-success" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com -s jina --json >"$forced_jina_json"
assert_json_success "$forced_jina_json" "jina"

schemeless_host_port_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-success" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" "localhost:$PORT/demo" -s jina --json >"$schemeless_host_port_json"
assert_json_success "$schemeless_host_port_json" "jina"
assert_json_url_equals "$schemeless_host_port_json" "https://localhost:$PORT/demo"

markdown_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-success" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com --json >"$markdown_json"
assert_json_success "$markdown_json" "markdown"

defuddle_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-success" \
    bash "$SCRIPT_PATH" example.com --json >"$defuddle_json"
assert_json_success "$defuddle_json" "defuddle"

basic_json="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" "http://127.0.0.1:$PORT/basic-success" --json >"$basic_json"
assert_json_success "$basic_json" "basic"

failure_json="$(mktemp)"
set +e
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" "http://127.0.0.1:$PORT/basic-short" --json >"$failure_json"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "--json failure should exit non-zero"
assert_json_failure "$failure_json" "none"

unsupported_scheme_json="$(mktemp)"
set +e
bash "$SCRIPT_PATH" "ftp://example.com" --json >"$unsupported_scheme_json"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "unsupported scheme should exit non-zero"
assert_json_failure "$unsupported_scheme_json" "none"
assert_json_error_contains "$unsupported_scheme_json" "Unsupported URL scheme"

invalid_charset_json="$(mktemp)"
invalid_charset_stderr="$(mktemp)"
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-invalid-charset" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com -s jina --json >"$invalid_charset_json" 2>"$invalid_charset_stderr"
assert_json_success "$invalid_charset_json" "jina"
assert_file_not_contains "$invalid_charset_stderr" "Traceback"

malformed_url_json="$(mktemp)"
malformed_url_stderr="$(mktemp)"
set +e
bash "$SCRIPT_PATH" "[::1]extra" --json >"$malformed_url_json" 2>"$malformed_url_stderr"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "malformed URL should exit non-zero"
assert_json_failure "$malformed_url_json" "none"
assert_json_error_contains "$malformed_url_json" "Invalid URL:"
assert_file_not_contains "$malformed_url_stderr" "Traceback"

markdown_short_json="$(mktemp)"
set +e
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-short" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com -s markdown --json >"$markdown_short_json"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "short extracted markdown should exit non-zero"
assert_json_failure "$markdown_short_json" "markdown"
assert_json_error_contains "$markdown_short_json" "too-short"

defuddle_short_json="$(mktemp)"
set +e
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-short" \
    bash "$SCRIPT_PATH" example.com -s defuddle --json >"$defuddle_short_json"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "short extracted defuddle should exit non-zero"
assert_json_failure "$defuddle_short_json" "defuddle"
assert_json_error_contains "$defuddle_short_json" "too-short"

binary_failure_json="$(mktemp)"
set +e
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-error" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" "http://127.0.0.1:$PORT/basic-binary" --json >"$binary_failure_json"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "binary basic fallback should exit non-zero"
assert_json_failure "$binary_failure_json" "none"
assert_json_error_contains "$binary_failure_json" "non-text/binary content"

parse_failure_output="$(mktemp)"
set +e
bash "$SCRIPT_PATH" --json --output "$parse_failure_output" >/dev/null
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "parse-time --json failure should exit non-zero"
assert_json_failure "$parse_failure_output" "none"

write_failure_json="$(mktemp)"
write_failure_stderr="$(mktemp)"
set +e
SMART_WEB_FETCH_JINA_READER_BASE="http://127.0.0.1:$PORT/jina-success" \
SMART_WEB_FETCH_MARKDOWN_NEW_URL="http://127.0.0.1:$PORT/markdown-error" \
SMART_WEB_FETCH_DEFUDDLE_URL="http://127.0.0.1:$PORT/defuddle-error" \
    bash "$SCRIPT_PATH" example.com --json --output . >"$write_failure_json" 2>"$write_failure_stderr"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "write-failure --json should exit non-zero"
assert_json_failure "$write_failure_json" "jina"
if grep -q "Traceback" "$write_failure_stderr"; then
    fail "write failure should not emit a Python traceback"
fi

echo "[PASS] Bash JSON smoke tests passed"
