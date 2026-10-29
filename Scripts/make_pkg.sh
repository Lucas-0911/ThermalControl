#!/bin/bash
# Personal artifacts signed with an Apple Development identity; not notarized distribution.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Invalid version: $VERSION" >&2; exit 1; }
NAME="ThermalControl"
APP_NAME="Thermal Control.app"
OUT="${1:-$ROOT/.build/packages/$VERSION}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
if [[ "$OUT" == "$ROOT/dist" || "$OUT" == "$ROOT/dist/"* ]]; then
  echo "Không ghi đè tracked dist; chọn output khác" >&2
  exit 1
fi
PKG="$OUT/${NAME}-${VERSION}.pkg"
DMG="$OUT/${NAME}-${VERSION}.dmg"
[[ ! -e "$PKG" && ! -e "$DMG" ]] || { echo "Artifact đã tồn tại; chọn output khác" >&2; exit 1; }

SIGN_ID="${SIGNING_IDENTITY:-$(security find-identity -p codesigning -v | awk '/"Apple Development:/ && !identity {identity=$2} END {print identity}')}"
[[ -n "$SIGN_ID" && "$SIGN_ID" != - ]] || { echo "Cần Apple Development signing identity; không dùng ad-hoc" >&2; exit 1; }
WORK="$(mktemp -d "$OUT/.packaging.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
DD="$WORK/DerivedData"
PKGROOT="$WORK/payload"
SCRIPTS="$WORK/scripts"
DMG_DIR="$WORK/dmg"

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate

echo "==> Build Release"
xcodebuild \
  -project ThermalControl.xcodeproj \
  -scheme ThermalControl \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DD/Build/Products/Release/$APP_NAME"
HELPER_BIN="$DD/Build/Products/Release/ThermalControlHelper"
[[ -d "$APP" && -x "$HELPER_BIN" ]] || { echo "Thiếu app/helper Release" >&2; exit 1; }

echo "==> Chuẩn bị payload trước khi ký"
mkdir -p "$PKGROOT/Applications" "$SCRIPTS" "$DMG_DIR"
ditto "$APP" "$PKGROOT/Applications/$APP_NAME"
PAYLOAD_APP="$PKGROOT/Applications/$APP_NAME"
rm -f "$PAYLOAD_APP/Contents/MacOS/"*.debug.dylib \
      "$PAYLOAD_APP/Contents/MacOS/__preview.dylib"
mkdir -p "$PAYLOAD_APP/Contents/Resources"
cp "$ROOT/Scripts/install_helper.sh" "$PAYLOAD_APP/Contents/Resources/install_helper.sh"
find "$PAYLOAD_APP" -type d -exec chmod 755 {} +
find "$PAYLOAD_APP" -type f -exec chmod 644 {} +
find "$PAYLOAD_APP/Contents/MacOS" -type f -exec chmod 755 {} +
chmod 755 "$PAYLOAD_APP/Contents/Resources/install_helper.sh"
xattr -cr "$PAYLOAD_APP"
find "$PAYLOAD_APP" -name '._*' -delete

echo "==> Ký payload cuối cùng"
codesign -s "$SIGN_ID" -f --timestamp=none --options runtime \
  --entitlements "$ROOT/Helper/ThermalControlHelper.entitlements" "$HELPER_BIN"
cp "$HELPER_BIN" "$PAYLOAD_APP/Contents/MacOS/ThermalControlHelper"
codesign -s "$SIGN_ID" -f --timestamp=none --options runtime \
  --entitlements "$ROOT/App/ThermalControl.entitlements" "$PAYLOAD_APP"
APP_REQUIREMENT='anchor apple generic and identifier "com.thermalcontrol.app"'
codesign --verify --strict --deep --all-architectures -R="$APP_REQUIREMENT" "$PAYLOAD_APP"
SIGN_INFO="$(codesign -d --verbose=4 "$PAYLOAD_APP" 2>&1)"
[[ "$SIGN_INFO" == *$'\nAuthority=Apple Development: '* ]] || { echo "Cần chữ ký Apple Development" >&2; exit 1; }
TEAM="$(printf '%s\n' "$SIGN_INFO" | awk -F= '/^TeamIdentifier=/{print $2}')"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Missing signing Team ID" >&2; exit 1; }
APP_REQUIREMENT="$APP_REQUIREMENT and certificate leaf[subject.OU] = \"$TEAM\""
HELPER_REQUIREMENT="anchor apple generic and identifier \"com.thermalcontrol.helper\" and certificate leaf[subject.OU] = \"$TEAM\""
codesign --verify --strict --deep --all-architectures -R="$APP_REQUIREMENT" "$PAYLOAD_APP"
codesign --verify --strict --all-architectures -R="$HELPER_REQUIREMENT" "$PAYLOAD_APP/Contents/MacOS/ThermalControlHelper"

cp "$ROOT/Scripts/postinstall" "$SCRIPTS/postinstall"
cp "$ROOT/Scripts/install_helper.sh" "$SCRIPTS/install_helper.sh"
chmod 755 "$SCRIPTS/postinstall" "$SCRIPTS/install_helper.sh"
echo "==> Tạo $PKG"
pkgbuild \
  --root "$PKGROOT" \
  --install-location / \
  --scripts "$SCRIPTS" \
  --identifier com.thermalcontrol.app \
  --version "$VERSION" \
  --ownership recommended \
  "$WORK/$NAME.pkg"

ditto "$PAYLOAD_APP" "$DMG_DIR/$APP_NAME"
ln -s /Applications "$DMG_DIR/Applications"
codesign --verify --strict --deep --all-architectures -R="$APP_REQUIREMENT" "$DMG_DIR/$APP_NAME"
echo "==> Tạo $DMG"
hdiutil create -volname "Thermal Control" -srcfolder "$DMG_DIR" -format UDZO "$WORK/$NAME.dmg" >/dev/null
# Hard links publish atomically without overwriting an artifact created by another run.
ln "$WORK/$NAME.pkg" "$PKG"
ln "$WORK/$NAME.dmg" "$DMG"
printf '\nXong (personal Apple Development; chưa notarize):\n  %s\n  %s\n' "$PKG" "$DMG"
