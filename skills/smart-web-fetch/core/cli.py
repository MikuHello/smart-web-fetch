from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from urllib import parse

from .errors import CLIError
from .output import emit_json_failure, inspect_cli_mode, output_error_message, render_payload, write_output
from .rules import load_rules
from .sources import run_fetch


VALID_SERVICES = {"jina", "markdown", "defuddle"}
ERROR_PREFIX = "smart-web-fetch: error: "
INTERPRETER_ERROR = (
    "smart-web-fetch: error: Python 3.11+ was not found. "
    "Install Python 3.11 or newer and ensure a compatible interpreter is on PATH."
)

_IPV4_RE = re.compile(r"^(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}$")
_HOST_WITH_PORT_RE = re.compile(r"^(?P<host>.+?)(?::(?P<port>\d+))?$")


@dataclass
class Config:
    url: str | None = None
    output: str | None = None
    service: str | None = None
    json_output: bool = False
    verbose: bool = False
    no_clean: bool = False
    help_requested: bool = False


def show_help() -> str:
    return """Smart Web Fetch - lightweight web-to-Markdown fetcher

Usage:
    smart-web-fetch <URL> [options]

Options:
    -h, --help          Show help
    -o, --output FILE   Write output to file
    -s, --service NAME  Force service: jina|markdown|defuddle
    --json              Emit a structured JSON object
    -v, --verbose       Show verbose logs
    --no-clean          Skip HTML cleanup in the basic fallback

Examples:
    smart-web-fetch https://example.com
    smart-web-fetch https://example.com -o output.md
    smart-web-fetch https://example.com -s jina
    smart-web-fetch https://example.com --json
    smart-web-fetch https://example.com --no-clean

Fallback order:
    1. Jina Reader
    2. markdown.new
    3. defuddle.md
    4. direct/basic fallback
"""


def normalize_url(url: str) -> str:
    if not url:
        raise CLIError("Please provide a URL")
    candidate = url.strip()
    if not candidate:
        raise CLIError("Please provide a URL")

    explicit_scheme = "://" in candidate
    if explicit_scheme:
        parsed = _split_url_or_raise(candidate)
    elif _is_host_like_input(candidate):
        candidate = f"https://{candidate}"
        parsed = _split_url_or_raise(candidate)
    else:
        parsed = _split_url_or_raise(candidate)

    scheme = parsed.scheme.lower()
    if explicit_scheme or parsed.scheme:
        if scheme not in {"http", "https"}:
            raise CLIError(f"Unsupported URL scheme: {parsed.scheme}")
    else:
        candidate = f"https://{candidate}"
        parsed = _split_url_or_raise(candidate)
        scheme = parsed.scheme.lower()

    if scheme not in {"http", "https"}:
        raise CLIError(f"Unsupported URL scheme: {parsed.scheme}")
    if not parsed.netloc:
        raise CLIError("Invalid URL: missing host")
    return parse.urlunsplit((scheme, parsed.netloc, parsed.path, parsed.query, parsed.fragment))


def _is_host_like_input(candidate: str) -> bool:
    authority = candidate.split("/", 1)[0].split("?", 1)[0].split("#", 1)[0]
    if not authority:
        return False
    if authority.startswith("["):
        closing = authority.find("]")
        if closing == -1:
            return False
        host = authority[: closing + 1]
        rest = authority[closing + 1 :]
        return _is_host_like_host(host) and (not rest or bool(re.fullmatch(r":\d+", rest)))

    if ":" not in authority:
        return _is_host_like_host(authority)

    match = _HOST_WITH_PORT_RE.fullmatch(authority)
    if not match or match.group("port") is None:
        return False
    host = match.group("host") or ""
    return _is_host_like_host(host)


def _is_host_like_host(host: str) -> bool:
    return host == "localhost" or "." in host or bool(_IPV4_RE.fullmatch(host)) or _is_bracketed_ipv6(host)


def _is_bracketed_ipv6(host: str) -> bool:
    if not (host.startswith("[") and host.endswith("]")):
        return False
    literal = host[1:-1]
    return bool(literal) and ":" in literal


def _split_url_or_raise(candidate: str) -> parse.SplitResult:
    try:
        return parse.urlsplit(candidate)
    except ValueError as exc:
        raise CLIError(f"Invalid URL: {exc}") from exc


def parse_args(argv: list[str]) -> Config:
    config = Config()
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in ("-h", "--help"):
            config.help_requested = True
            break
        if arg == "--json":
            config.json_output = True
            index += 1
            continue
        if arg in ("-v", "--verbose"):
            config.verbose = True
            index += 1
            continue
        if arg == "--no-clean":
            config.no_clean = True
            index += 1
            continue
        if arg in ("-o", "--output"):
            if index + 1 >= len(argv):
                raise CLIError(f"Missing value for {arg}")
            value = argv[index + 1]
            if value.startswith("-"):
                raise CLIError(f"Invalid value for {arg}: {value}")
            config.output = value
            index += 2
            continue
        if arg.startswith("--output="):
            value = arg.split("=", 1)[1]
            if not value or value.startswith("-"):
                raise CLIError("Invalid value for --output")
            config.output = value
            index += 1
            continue
        if arg in ("-s", "--service"):
            if index + 1 >= len(argv):
                raise CLIError(f"Missing value for {arg}")
            value = argv[index + 1]
            if value.startswith("-"):
                raise CLIError(f"Invalid value for {arg}: {value}")
            if value not in VALID_SERVICES:
                raise CLIError(f"Invalid service: {value}. Allowed values: jina|markdown|defuddle", source=value)
            config.service = value
            index += 2
            continue
        if arg.startswith("--service="):
            value = arg.split("=", 1)[1]
            if value not in VALID_SERVICES:
                raise CLIError(f"Invalid service: {value}. Allowed values: jina|markdown|defuddle", source=value or "none")
            config.service = value
            index += 1
            continue
        if arg.startswith("-"):
            raise CLIError(f"Unknown option: {arg}", source=config.service)
        if config.url is not None:
            raise CLIError("Only one URL argument is allowed", source=config.service)
        config.url = arg
        index += 1

    if not config.help_requested and config.url is None:
        raise CLIError("Please provide a URL", source=config.service)
    return config


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    json_output, requested_output = inspect_cli_mode(args)

    try:
        config = parse_args(args)
    except CLIError as exc:
        if json_output:
            return emit_json_failure("", exc.source, str(exc), requested_output)
        print(f"{ERROR_PREFIX}{exc}", file=sys.stderr)
        return 1

    if config.help_requested:
        sys.stdout.write(show_help())
        return 0

    try:
        normalized_url = normalize_url(config.url or "")
    except CLIError as exc:
        if config.json_output:
            return emit_json_failure(config.url or "", config.service or "none", str(exc), config.output)
        print(f"{ERROR_PREFIX}{exc}", file=sys.stderr)
        return 1

    config.url = normalized_url
    rules = load_rules(config.verbose)

    try:
        result = run_fetch(config, rules)
        payload = result.content
        if config.json_output:
            payload = render_payload(True, normalized_url, result.content, result.source)
        try:
            write_output(payload, config.output)
        except Exception as exc:
            message = output_error_message(config.output, exc)
            if config.json_output:
                return emit_json_failure(normalized_url, result.source, message)
            print(f"{ERROR_PREFIX}{message}", file=sys.stderr)
            return 1
        return 0
    except CLIError as exc:
        if config.json_output:
            failure_source = config.service or "none"
            return emit_json_failure(normalized_url, failure_source, str(exc), config.output)
        print(f"{ERROR_PREFIX}{exc}", file=sys.stderr)
        return 1
