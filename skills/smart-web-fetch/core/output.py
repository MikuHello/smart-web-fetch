from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path


def log(verbose: bool, level: str, message: str) -> None:
    if verbose:
        print(f"[{level}] {message}", file=sys.stderr)


def render_payload(success: bool, url: str, content: str, source: str, error_message: str | None = None) -> str:
    payload = {
        "success": success,
        "url": url,
        "content": content,
        "source": source,
    }
    if error_message:
        payload["error"] = error_message
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def inspect_cli_mode(argv: list[str]) -> tuple[bool, str | None]:
    json_output = False
    output: str | None = None
    index = 0

    while index < len(argv):
        arg = argv[index]
        if arg == "--json":
            json_output = True
        elif arg in ("-o", "--output"):
            if index + 1 < len(argv):
                value = argv[index + 1]
                if value and not value.startswith("-"):
                    output = value
                index += 1
        elif arg.startswith("--output="):
            value = arg.split("=", 1)[1]
            if value and not value.startswith("-"):
                output = value
        index += 1

    return json_output, output


def write_output(payload: str, destination: str | None) -> None:
    if not destination:
        sys.stdout.write(payload)
        if not payload.endswith("\n"):
            sys.stdout.write("\n")
        return
    target = Path(destination)
    if target.parent and not target.parent.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=f".{target.name}.tmp.", dir=str(target.parent or Path.cwd()))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(payload)
            if not payload.endswith("\n"):
                handle.write("\n")
        os.replace(tmp_path, target)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def output_error_message(destination: str | None, exc: Exception) -> str:
    if destination:
        return f"Failed to write output to {destination}: {exc}"
    return f"Failed to write output: {exc}"


def emit_json_failure(url: str, source: str, error_message: str, destination: str | None = None) -> int:
    payload = render_payload(False, url, "", source, error_message)

    if destination:
        try:
            write_output(payload, destination)
            return 1
        except Exception as exc:
            payload = render_payload(
                False,
                url,
                "",
                source,
                f"{error_message}; {output_error_message(destination, exc)}",
            )

    write_output(payload, None)
    return 1
