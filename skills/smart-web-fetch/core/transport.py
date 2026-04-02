from __future__ import annotations

from dataclasses import dataclass
from urllib import error, request

from .errors import FetchTransportError


TIMEOUT_SECONDS = 30


@dataclass
class ResponseData:
    status_code: int
    content_type: str
    raw_body: bytes
    text: str


def decode_response_body(body: bytes, headers) -> str:
    charset = None
    try:
        charset = headers.get_content_charset()
    except AttributeError:
        charset = None

    encodings: list[str] = []
    if charset:
        encodings.append(charset)
    if body.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings.append("utf-16")
    encodings.extend(["utf-8", "latin-1"])

    for encoding in encodings:
        try:
            return body.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue
    return body.decode("utf-8", errors="replace")


def get_media_type(content_type: str) -> str:
    return (content_type or "").split(";", 1)[0].strip().lower()


def is_text_media_type(content_type: str) -> bool:
    media_type = get_media_type(content_type)
    if not media_type:
        return False
    if media_type.startswith("text/"):
        return True
    return media_type in {
        "application/json",
        "application/xml",
        "application/xhtml+xml",
        "application/javascript",
        "application/x-javascript",
        "application/x-www-form-urlencoded",
    } or media_type.endswith(("+json", "+xml"))


def is_binary_media_type(content_type: str) -> bool:
    media_type = get_media_type(content_type)
    if not media_type:
        return False
    if media_type.startswith(("image/", "audio/", "video/")):
        return True
    return media_type in {
        "application/octet-stream",
        "application/pdf",
        "application/zip",
        "application/x-zip-compressed",
        "application/gzip",
        "application/x-gzip",
        "application/x-tar",
        "application/x-bzip2",
        "application/x-7z-compressed",
        "application/vnd.rar",
        "application/x-rar-compressed",
    }


def has_binary_body_signature(body: bytes) -> bool:
    if not body:
        return False
    if b"\x00" in body:
        return True
    sample = body[:1024]
    try:
        sample.decode("utf-8")
        return False
    except UnicodeDecodeError:
        pass
    non_printable = sum(byte < 32 and byte not in (9, 10, 13, 12, 8) for byte in sample)
    return non_printable / max(len(sample), 1) >= 0.30


def is_binary_response(content_type: str, body: bytes) -> bool:
    if is_binary_media_type(content_type):
        return True
    if is_text_media_type(content_type):
        return False
    return has_binary_body_signature(body)


def request_text(url: str, method: str = "GET", headers: dict[str, str] | None = None, body: bytes | None = None) -> ResponseData:
    req = request.Request(url=url, data=body, headers=headers or {}, method=method)
    try:
        with request.urlopen(req, timeout=TIMEOUT_SECONDS) as response:
            status_code = getattr(response, "status", response.getcode())
            content_type = response.headers.get("Content-Type", "")
            raw_body = response.read()
            text = decode_response_body(raw_body, response.headers)
            return ResponseData(status_code=status_code, content_type=content_type, raw_body=raw_body, text=text)
    except error.HTTPError as exc:
        content_type = exc.headers.get("Content-Type", "") if exc.headers else ""
        raw_body = exc.read()
        text = decode_response_body(raw_body, exc.headers or {})
        return ResponseData(status_code=exc.code, content_type=content_type, raw_body=raw_body, text=text)
    except error.URLError as exc:
        reason = exc.reason if getattr(exc, "reason", None) else exc
        raise FetchTransportError(str(reason)) from exc
    except OSError as exc:
        raise FetchTransportError(str(exc)) from exc
