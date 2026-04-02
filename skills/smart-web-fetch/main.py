from __future__ import annotations

import sys
from pathlib import Path


INTERPRETER_ERROR = (
    "smart-web-fetch: error: Python 3.11+ was not found. "
    "Install Python 3.11 or newer and ensure a compatible interpreter is on PATH."
)

SKILL_DIR = Path(__file__).resolve().parent
SKILL_DIR_STR = str(SKILL_DIR)

try:
    sys.path.remove(SKILL_DIR_STR)
except ValueError:
    pass
sys.path.insert(0, SKILL_DIR_STR)

if sys.version_info < (3, 11):
    print(INTERPRETER_ERROR, file=sys.stderr)
    raise SystemExit(1)

from core.cli import main as cli_main


if __name__ == "__main__":
    raise SystemExit(cli_main())
