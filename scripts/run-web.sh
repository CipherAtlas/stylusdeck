#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  printf "[run-web] python3 is required for the web UI. Install it with Homebrew: brew install python\n" >&2
  exit 1
fi

python3 - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 9) else 1)
PY

exec python3 server.py
