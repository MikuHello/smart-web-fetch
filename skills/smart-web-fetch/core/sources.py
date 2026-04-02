from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable
from urllib import parse

from .errors import CLIError, FetchTransportError
from .extract import clean_html, html_to_text, looks_like_html
from .output import log
from .rules import Rules, contains_keyword
from .transport import is_binary_response, request_text

if TYPE_CHECKING:
    from .cli import Config


JINA_READER_BASE = os.environ.get("SMART_WEB_FETCH_JINA_READER_BASE", "https://r.jina.ai")
MARKDOWN_NEW_URL = os.environ.get("SMART_WEB_FETCH_MARKDOWN_NEW_URL", "https://api.markdown.new/api/v1/convert")
DEFUDDLE_URL = os.environ.get("SMART_WEB_FETCH_DEFUDDLE_URL", "https://defuddle.md/api/convert")


@dataclass
class FetchResult:
    content: str
    source: str


def parse_json_object(text: str) -> dict[str, object] | None:
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    if isinstance(value, dict):
        return value
    return None


def is_structured_error_response(text: str, rules: Rules) -> bool:
    payload = parse_json_object(text)
    if payload is None:
        return False
    error_value = payload.get("error")
    if error_value is True:
        return True
    if isinstance(error_value, str) and contains_keyword(error_value, rules.structured_error_keywords):
        return True
    message_value = payload.get("message")
    if isinstance(message_value, str) and contains_keyword(message_value, rules.structured_error_keywords):
        return True
    return False


def is_likely_html_error_payload(text: str, content_type: str, rules: Rules) -> bool:
    lowered_type = (content_type or "").lower()
    if "text/html" not in lowered_type and "application/xhtml+xml" not in lowered_type:
        return False
    lowered_text = text.lower()
    if "<html" not in lowered_text and "<title" not in lowered_text:
        return False
    return contains_keyword(lowered_text, rules.html_error_keywords)


def build_jina_url(target_url: str) -> str:
    parsed = parse.urlsplit(target_url)
    scheme = (parsed.scheme or "http").lower()
    suffix = target_url.split("://", 1)[1] if "://" in target_url else target_url
    return f"{JINA_READER_BASE.rstrip('/')}/{scheme}://{suffix}"


def extract_markdown_field(text: str) -> tuple[str | None, bool]:
    payload = parse_json_object(text)
    if payload is None:
        return None, False
    for key in ("markdown", "content", "data"):
        if key not in payload or payload[key] is None:
            continue
        value = payload[key]
        if isinstance(value, str):
            return value, True
        if isinstance(value, (dict, list)):
            return json.dumps(value, ensure_ascii=False, separators=(",", ":")), True
        return str(value), True
    return None, True


def ensure_min_length(source: str, label: str, text: str, minimum: int) -> str:
    if len(text) < minimum:
        raise CLIError(f"{label} returned empty or too-short content", source=source)
    return text


def extract_service_content(source: str, label: str, response_text: str, minimum: int) -> str:
    markdown, is_json_object = extract_markdown_field(response_text)
    if is_json_object:
        if markdown is None or markdown == "":
            raise CLIError(f"{label} returned JSON without usable markdown/content/data", source=source)
        return ensure_min_length(source, label, markdown, minimum)
    return ensure_min_length(source, label, response_text, minimum)


def fetch_jina(url: str, rules: Rules, verbose: bool) -> FetchResult:
    log(verbose, "INFO", "Trying Jina Reader")
    try:
        response = request_text(
            build_jina_url(url),
            headers={"User-Agent": "SmartWebFetch/1.0"},
        )
    except FetchTransportError as exc:
        raise CLIError(f"Jina Reader request failed: {exc}", source="jina") from exc
    if not 200 <= response.status_code < 300:
        raise CLIError(f"Jina Reader returned HTTP {response.status_code}", source="jina")
    if is_structured_error_response(response.text, rules):
        raise CLIError("Jina Reader returned structured error payload", source="jina")
    return FetchResult(
        content=ensure_min_length("jina", "Jina Reader", response.text, rules.jina_min_length),
        source="jina",
    )


def fetch_markdown_new(url: str, rules: Rules, verbose: bool) -> FetchResult:
    log(verbose, "INFO", "Trying markdown.new")
    body = json.dumps({"url": url}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    try:
        response = request_text(
            MARKDOWN_NEW_URL,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "User-Agent": "SmartWebFetch/1.0",
            },
            body=body,
        )
    except FetchTransportError as exc:
        raise CLIError(f"markdown.new request failed: {exc}", source="markdown") from exc
    if not 200 <= response.status_code < 300:
        raise CLIError(f"markdown.new returned HTTP {response.status_code}", source="markdown")
    if is_likely_html_error_payload(response.text, response.content_type, rules):
        raise CLIError(
            f"markdown.new returned HTML error page (content-type: {response.content_type or 'unknown'})",
            source="markdown",
        )
    if is_structured_error_response(response.text, rules):
        raise CLIError("markdown.new returned structured error payload", source="markdown")
    content = extract_service_content("markdown", "markdown.new", response.text, rules.markdown_min_length)
    return FetchResult(content=content, source="markdown")


def fetch_defuddle(url: str, rules: Rules, verbose: bool) -> FetchResult:
    log(verbose, "INFO", "Trying defuddle.md")
    body = json.dumps({"url": url}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    try:
        response = request_text(
            DEFUDDLE_URL,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "User-Agent": "SmartWebFetch/1.0",
            },
            body=body,
        )
    except FetchTransportError as exc:
        raise CLIError(f"defuddle.md request failed: {exc}", source="defuddle") from exc
    if not 200 <= response.status_code < 300:
        raise CLIError(f"defuddle.md returned HTTP {response.status_code}", source="defuddle")
    if is_likely_html_error_payload(response.text, response.content_type, rules):
        raise CLIError(
            f"defuddle.md returned HTML error page (content-type: {response.content_type or 'unknown'})",
            source="defuddle",
        )
    if is_structured_error_response(response.text, rules):
        raise CLIError("defuddle.md returned structured error payload", source="defuddle")
    content = extract_service_content("defuddle", "defuddle.md", response.text, rules.defuddle_min_length)
    return FetchResult(content=content, source="defuddle")


def fetch_basic(url: str, rules: Rules, verbose: bool, no_clean: bool) -> FetchResult:
    log(verbose, "INFO", "Trying basic fallback")
    try:
        response = request_text(
            url,
            headers={
                "User-Agent": "Mozilla/5.0",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            },
        )
    except FetchTransportError as exc:
        raise CLIError(f"Basic fallback request failed: {exc}", source="basic") from exc
    if not 200 <= response.status_code < 300:
        raise CLIError(f"Basic fallback returned HTTP {response.status_code}", source="basic")
    if is_binary_response(response.content_type, response.raw_body):
        raise CLIError("Basic fallback returned non-text/binary content", source="basic")
    if len(response.text) < rules.basic_min_length:
        raise CLIError("Basic fallback returned empty or too-short content before cleanup", source="basic")
    processed = response.text
    if not no_clean and looks_like_html(response.text, response.content_type):
        cleaned_html = clean_html(response.text)
        if len(cleaned_html) < rules.basic_min_length:
            raise CLIError("Basic fallback returned empty or too-short content after HTML cleanup", source="basic")
        processed = html_to_text(cleaned_html)
    if len(processed) < rules.basic_min_length:
        raise CLIError("Basic fallback returned empty or too-short content after cleanup", source="basic")
    return FetchResult(content=processed, source="basic")


def run_fetch(config: Config, rules: Rules) -> FetchResult:
    if config.url is None:
        raise CLIError("Please provide a URL")
    log(config.verbose, "INFO", f"Fetching {config.url}")
    fetchers: dict[str, Callable[[], FetchResult]] = {
        "jina": lambda: fetch_jina(config.url, rules, config.verbose),
        "markdown": lambda: fetch_markdown_new(config.url, rules, config.verbose),
        "defuddle": lambda: fetch_defuddle(config.url, rules, config.verbose),
        "basic": lambda: fetch_basic(config.url, rules, config.verbose, config.no_clean),
    }
    if config.service:
        return fetchers[config.service]()
    last_error: CLIError | None = None
    for name in ("jina", "markdown", "defuddle", "basic"):
        try:
            return fetchers[name]()
        except CLIError as exc:
            last_error = exc
            log(config.verbose, "WARN", str(exc))
    if last_error is not None:
        raise CLIError(f"All fetch methods failed. Last error: {last_error}", source="none") from last_error
    raise CLIError("All fetch methods failed", source="none")
