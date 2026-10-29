#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Shared installer checks signatures and waits for successful restore before deleting anything.
exec /bin/bash "$SCRIPT_DIR/install_helper.sh" --uninstall "${1:-/Applications/Thermal Control.app}"
