#!/usr/bin/env bash
# Idempotent Cloud Agent setup for FinOps for Snowflake AI.
# Installs the Python venv used by the Streamlit dashboard. The training site
# is static HTML and needs no build step.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# The default image ships Python 3.12 but not the venv module; add it once.
if ! python3 -c "import ensurepip" >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3.12-venv
fi

if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
fi

.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -r dashboard/requirements.txt

echo "Environment ready: .venv created and dashboard dependencies installed."
