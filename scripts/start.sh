#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$REPO_ROOT/scripts/install.sh"

printf "\n==> Starting StylusDeck\n"
exec "$REPO_ROOT/scripts/run.sh"
