#!/bin/bash
# Đóng gói Thermal Control thành .pkg (installer macOS) và .dmg để chia sẻ.
# Không dùng .deb/.dpkg — đó là gói Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist" 2>/dev/null || echo "1.0.0")"
NAME="ThermalControl"
APP_NAME="Thermal Control.app"
OUT="$ROOT/dist"
DD="$ROOT/.build-release"
PKGROOT="$ROOT/.pkgroot"
SCRIPTS="$ROOT/.pkgscripts"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate

echo "==> Build Release"
xcodebuild \
  -project ThermalControl.xcodeproj \
  -scheme ThermalControl \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  build

APP="$DD/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP" ]]; then
  echo "Không thấy app Release: $APP"
  exit 1
fi

echo "==> Chuẩn bị payload"
rm -rf "$PKGROOT" "$SCRIPTS"
mkdir -p "$PKGROOT/Applications" "$SCRIPTS" "$OUT"
cp -R "$APP" "$PKGROOT/Applications/"
# Bỏ file debug nếu lỡ lẫn vào
rm -f "$PKGROOT/Applications/$APP_NAME/Contents/MacOS/"*.debug.dylib \
      "$PKGROOT/Applications/$APP_NAME/Contents/MacOS/__preview.dylib" 2>/dev/null || true
mkdir -p "$PKGROOT/Applications/$APP_NAME/Contents/Resources"
cp "$ROOT/Scripts/install_helper.sh" "$PKGROOT/Applications/$APP_NAME/Contents/Resources/install_helper.sh"
chmod 755 "$PKGROOT/Applications/$APP_NAME/Contents/Resources/install_helper.sh"

cp "$ROOT/Scripts/postinstall" "$SCRIPTS/postinstall"
chmod 755 "$SCRIPTS/postinstall"

PKG="$OUT/${NAME}-${VERSION}.pkg"
echo "==> Tạo $PKG"
pkgbuild \
  --root "$PKGROOT" \
  --install-location / \
  --scripts "$SCRIPTS" \
  --identifier com.thermalcontrol.app \
  --version "$VERSION" \
  --ownership recommended \
  "$PKG"

DMG_DIR="$ROOT/.dmgroot"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$PKGROOT/Applications/$APP_NAME" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
DMG="$OUT/${NAME}-${VERSION}.dmg"
rm -f "$DMG"
echo "==> Tạo $DMG"
hdiutil create -volname "Thermal Control" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$PKGROOT" "$SCRIPTS" "$DMG_DIR"
echo
echo "Xong:"
echo "  $PKG"
echo "  $DMG"
echo
echo "Gửi file .pkg cho người khác: double-click để cài vào /Applications và helper (cần mật khẩu máy)."
echo "Hoặc gửi .dmg: kéo app vào Applications, rồi chạy Scripts/install_helper.sh nếu chưa có helper."
