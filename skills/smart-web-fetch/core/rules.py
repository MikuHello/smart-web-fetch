from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .output import log


DEFAULT_RULES = {
    "thresholds": {
        "jina": 100,
        "markdown_new": 40,
        "defuddle": 40,
        "basic": 40,
    },
    "structured_error_keywords": [
        "error",
        "fail",
        "invalid",
        "unauthorized",
        "forbidden",
        "denied",
        "blocked",
        "not found",
        "rate limit",
        "too many requests",
    ],
    "html_error_keywords": [
        "access denied",
        "forbidden",
        "captcha",
        "cloudflare",
        "just a moment",
        "unauthorized",
        "bad gateway",
        "gateway timeout",
        "service unavailable",
    ],
}

PACKAGE_DIR = Path(__file__).resolve().parent
SKILL_DIR = PACKAGE_DIR.parent
RULES_FILE = SKILL_DIR / "assets" / "fetch-rules.json"


@dataclass
class Rules:
    jina_min_length: int
    markdown_min_length: int
    defuddle_min_length: int
    basic_min_length: int
    structured_error_keywords: list[str]
    html_error_keywords: list[str]


def load_rules(verbose: bool) -> Rules:
    data = json.loads(json.dumps(DEFAULT_RULES))
    if RULES_FILE.is_file():
        try:
            loaded = json.loads(RULES_FILE.read_text(encoding="utf-8"))
            thresholds = loaded.get("thresholds", {})
            for key in ("jina", "markdown_new", "defuddle", "basic"):
                value = thresholds.get(key)
                if isinstance(value, int) and value > 0:
                    data["thresholds"][key] = value
            structured = loaded.get("structured_error_keywords")
            if isinstance(structured, list) and structured:
                data["structured_error_keywords"] = [str(item) for item in structured if str(item).strip()]
            html_keywords = loaded.get("html_error_keywords")
            if isinstance(html_keywords, list) and html_keywords:
                data["html_error_keywords"] = [str(item) for item in html_keywords if str(item).strip()]
            log(verbose, "INFO", f"Loaded thresholds and keywords from rules file: {RULES_FILE}")
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            log(verbose, "WARN", f"Failed to parse rules file, using built-in defaults: {RULES_FILE}")
    return Rules(
        jina_min_length=data["thresholds"]["jina"],
        markdown_min_length=data["thresholds"]["markdown_new"],
        defuddle_min_length=data["thresholds"]["defuddle"],
        basic_min_length=data["thresholds"]["basic"],
        structured_error_keywords=list(data["structured_error_keywords"]),
        html_error_keywords=list(data["html_error_keywords"]),
    )


def normalize_keyword_text(text: str | None) -> str:
    if not text:
        return ""
    normalized = text.lower().replace("_", " ").replace("-", " ")
    return re.sub(r"\s+", " ", normalized).strip()


def contains_keyword(text: str | None, keywords: list[str]) -> bool:
    normalized_text = normalize_keyword_text(text)
    if not normalized_text:
        return False
    return any(normalize_keyword_text(keyword) in normalized_text for keyword in keywords if normalize_keyword_text(keyword))
