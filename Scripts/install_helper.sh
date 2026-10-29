#!/bin/bash
# Signed personal installs only. Restore must succeed before replacing/removing a helper.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

HELPER_NAME="ThermalControlHelper"
LABEL="com.thermalcontrol.helper"
DEST_HELPER="/Library/PrivilegedHelperTools/${HELPER_NAME}"
DEST_PLIST="/Library/LaunchDaemons/${LABEL}.plist"

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "Chạy với sudo: $0 /path/to/ThermalControlHelper [app] hoặc $0 --uninstall [app]"

MODE=install
if [[ "${1:-}" == --uninstall ]]; then
  MODE=uninstall
  APP="${2:-/Applications/Thermal Control.app}"
else
  SRC="${1:-}"
  [[ -n "$SRC" && -x "$SRC" && ! -L "$SRC" ]] || fail "Không thấy binary helper: $SRC"
  APP="${2:-$(dirname "$(dirname "$(dirname "$SRC")")")}"
fi
[[ -d "$APP" && ! -L "$APP" ]] || fail "Cần app đã ký để xác nhận restore: $APP"
[[ ! -L "$DEST_HELPER" && ! -L "$DEST_PLIST" && ! -L /Library/LaunchDaemons ]] || fail "Đường dẫn helper/daemon là symlink; giữ nguyên cài đặt"

mkdir -p /Library/PrivilegedHelperTools
[[ ! -L /Library/PrivilegedHelperTools && $(stat -f %u /Library/PrivilegedHelperTools) == 0 ]] || fail "PrivilegedHelperTools không đáng tin cậy"
[[ -z "$(find /Library/PrivilegedHelperTools -maxdepth 0 -perm +022 -print)" ]] || fail "PrivilegedHelperTools cho phép user ghi"
STAGE="$(mktemp -d /Library/PrivilegedHelperTools/.thermalcontrol-install.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
chmod -N "$STAGE"
STAGED_APP="$STAGE/Thermal Control.app"
ditto --noacl "$APP" "$STAGED_APP"
# ponytail: this app has no framework symlinks; reject links rather than resolve untrusted bundle paths.
[[ -z "$(find "$STAGED_APP" ! -type d ! -type f -print)" ]] || fail "App có symlink/special file; không dùng làm restore client"
chown -R root:wheel "$STAGED_APP"
chmod -RN "$STAGED_APP"
chmod -R u+rwX,go+rX,go-w "$STAGED_APP"
chmod 755 "$STAGE"

verify_code() {
  codesign --verify --strict --deep --all-architectures -R="$2" "$1" || fail "Chữ ký/identity không hợp lệ: $1"
}
APP_REQUIREMENT='anchor apple generic and identifier "com.thermalcontrol.app"'
verify_code "$STAGED_APP" "$APP_REQUIREMENT"
TEAM="$(codesign -d --verbose=4 "$STAGED_APP" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail "App thiếu Team ID hợp lệ"
APP_REQUIREMENT="$APP_REQUIREMENT and certificate leaf[subject.OU] = \"$TEAM\""
HELPER_REQUIREMENT="anchor apple generic and identifier \"com.thermalcontrol.helper\" and certificate leaf[subject.OU] = \"$TEAM\""
verify_code "$STAGED_APP" "$APP_REQUIREMENT"

if [[ "$MODE" == install ]]; then
  cp "$SRC" "$STAGE/$HELPER_NAME"
  chmod 755 "$STAGE/$HELPER_NAME"
  verify_code "$STAGE/$HELPER_NAME" "$HELPER_REQUIREMENT"
  verify_code "$STAGED_APP/Contents/MacOS/$HELPER_NAME" "$HELPER_REQUIREMENT"
  cmp -s "$STAGE/$HELPER_NAME" "$STAGED_APP/Contents/MacOS/$HELPER_NAME" || fail "Helper không khớp app"
fi

if [[ "$MODE" == uninstall || -e "$DEST_HELPER" || -e "$DEST_PLIST" ]] || launchctl print "system/$LABEL" >/dev/null 2>&1; then
  [[ -x "$DEST_HELPER" && ! -L "$DEST_HELPER" ]] || fail "Không xác minh được helper hiện tại; giữ nguyên cài đặt"
  verify_code "$DEST_HELPER" "$HELPER_REQUIREMENT"
  RESTORE_USER="${SUDO_USER:-}"
  if [[ -z "$RESTORE_USER" || "$RESTORE_USER" == root ]]; then
    RESTORE_USER="$(stat -f %Su /dev/console)"
  fi
  [[ -n "$RESTORE_USER" && "$RESTORE_USER" != root && "$RESTORE_USER" != loginwindow ]] || fail "Cần user đăng nhập để restore; chưa thay/xóa helper"
  RESTORE_UID="$(id -u "$RESTORE_USER")"
  [[ "$RESTORE_UID" -ne 0 ]] || fail "Không chạy restore app với quyền root"
  RESTORE_BIN="$STAGED_APP/Contents/MacOS/Thermal Control"
  [[ -x "$RESTORE_BIN" ]] || fail "Thiếu restore client"
  RESTORE_FLAG=--release-transient-control
  [[ "$MODE" != uninstall ]] || RESTORE_FLAG=--restore-system-control
  echo "Xác nhận $RESTORE_FLAG trước khi dừng helper..."
  /usr/bin/sudo -H -u "$RESTORE_USER" /usr/bin/env -i PATH="$PATH" \
    "$RESTORE_BIN" "$RESTORE_FLAG" || fail "Restore chưa xác nhận (helper protocol cũ không tự migration); giữ nguyên helper và state"
fi

if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "system/$LABEL"
fi

if [[ "$MODE" == uninstall ]]; then
  rm -f "$DEST_PLIST" "$DEST_HELPER"
  rm -rf "/Library/Application Support/ThermalControl"
  echo "Đã restore và gỡ helper + state.json."
  exit 0
fi

cp -f "$STAGE/$HELPER_NAME" "$DEST_HELPER"
chown root:wheel "$DEST_HELPER"
chmod 755 "$DEST_HELPER"
verify_code "$DEST_HELPER" "$HELPER_REQUIREMENT"

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
