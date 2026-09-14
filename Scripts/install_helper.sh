#!/bin/bash
# Cài helper bằng LaunchDaemon (cách chắc nhất khi chưa notarize / SMAppService).
# Chạy SAU KHI đã build 2 binary.
set -euo pipefail

APP_NAME="Thermal Control.app"
HELPER_NAME="ThermalControlHelper"
LABEL="com.thermalcontrol.helper"
DEST_HELPER="/Library/PrivilegedHelperTools/${HELPER_NAME}"
DEST_PLIST="/Library/LaunchDaemons/${LABEL}.plist"

if [[ $EUID -ne 0 ]]; then
  echo "Chạy lại với sudo: sudo $0 /đường/dẫn/tới/ThermalControlHelper"
  exit 1
fi

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  echo "Usage: sudo $0 /path/to/ThermalControlHelper"
  exit 1
fi
if [[ ! -x "$SRC" ]]; then
  echo "Không thấy binary helper: $SRC"
  exit 1
fi

echo "Restore quạt trước khi thay helper (nếu helper cũ đang chạy)..."
launchctl bootout system/${LABEL} 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools
cp -f "$SRC" "$DEST_HELPER"
chown root:wheel "$DEST_HELPER"
chmod 755 "$DEST_HELPER"

cat > "$DEST_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DEST_HELPER}</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>${LABEL}</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/thermalcontrol-helper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/thermalcontrol-helper.err</string>
</dict>
</plist>
PLIST

chown root:wheel "$DEST_PLIST"
chmod 644 "$DEST_PLIST"
launchctl bootstrap system "$DEST_PLIST"
echo "OK — helper đã cài. Log: /tmp/thermalcontrol-helper.log"
echo "Mở app menu bar và bấm Kết nối lại."
