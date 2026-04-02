#!/usr/bin/env python3

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


ROOT_DIR = Path(__file__).resolve().parents[2]
FIXTURE_DIR = ROOT_DIR / "spec" / "fixtures"
MARKDOWN_SUCCESS = json.loads((FIXTURE_DIR / "markdown-success.json").read_text(encoding="utf-8"))["markdown"]
JINA_SUCCESS = f"{MARKDOWN_SUCCESS}\n\n{MARKDOWN_SUCCESS}"
SHORT_EXTRACTED_JSON = json.dumps({"markdown": "tiny", "meta": "x" * 200}, ensure_ascii=False, separators=(",", ":"))
STRUCTURED_ERROR = (FIXTURE_DIR / "structured-error.json").read_text(encoding="utf-8")
TOO_SHORT = (FIXTURE_DIR / "too-short.txt").read_text(encoding="utf-8")
BASIC_BINARY = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"


class Handler(BaseHTTPRequestHandler):
    server_version = "SmartWebFetchTest/1.0"

    def log_message(self, format, *args):
        return

    def _write(self, status, body, content_type):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _write_with_charset(self, status, body, content_type, charset):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", f"{content_type}; charset={charset}")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _write_bytes(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path

        if path.startswith("/jina-success/"):
            self._write(200, JINA_SUCCESS, "text/plain")
            return

        if path.startswith("/jina-error/"):
            self._write(200, STRUCTURED_ERROR, "application/json")
            return

        if path.startswith("/jina-invalid-charset/"):
            self._write_with_charset(200, JINA_SUCCESS, "text/plain", "not-a-real-charset")
            return

        if path == "/basic-success":
            html = (
                "<html><head><title>Basic Success</title></head>"
                "<body><main><article>"
                f"<h1>Title</h1><p>{MARKDOWN_SUCCESS}</p><p>{MARKDOWN_SUCCESS}</p>"
                "</article></main></body></html>"
            )
            self._write(200, html, "text/html")
            return

        if path == "/basic-short":
            self._write(200, TOO_SHORT, "text/plain")
            return

        if path == "/basic-binary":
            self._write_bytes(200, BASIC_BINARY, "image/png")
            return

        self._write(404, "not found", "text/plain")

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)

        if path in {"/markdown-success", "/defuddle-success"}:
            self._write(200, (FIXTURE_DIR / "markdown-success.json").read_text(encoding="utf-8"), "application/json")
            return

        if path in {"/markdown-short", "/defuddle-short"}:
            self._write(200, SHORT_EXTRACTED_JSON, "application/json")
            return

        if path in {"/markdown-error", "/defuddle-error"}:
            self._write(200, STRUCTURED_ERROR, "application/json")
            return

        self._write(404, "not found", "text/plain")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
