#!/bin/bash
set -euo pipefail
LABEL="com.thermalcontrol.helper"
if [[ $EUID -ne 0 ]]; then
  echo "Chạy: sudo $0"
  exit 1
fi
launchctl bootout system/${LABEL} 2>/dev/null || true
rm -f /Library/LaunchDaemons/${LABEL}.plist
rm -f /Library/PrivilegedHelperTools/ThermalControlHelper
rm -rf "/Library/Application Support/ThermalControl"
echo "Đã gỡ helper + state.json."
