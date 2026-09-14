# Đóng gói Thermal Control để gửi người khác

## `.dpkg` hay `.pkg`?

| Hệ | File cài |
|---|---|
| Linux (Debian/Ubuntu) | `.deb` / lệnh `dpkg` |
| **macOS (app này)** | **`.pkg`** (installer) và/hoặc **`.dmg`** |

Không build được `.dpkg` cho Mac. Dùng script có sẵn để ra **`.pkg`**.

---

## 1. Chuẩn bị máy build (một lần)

1. Cài **Xcode** từ App Store, mở một lần, Agree.
2. Xcode → **Settings → Accounts** → thêm Apple ID.
3. Terminal:

```bash
# Trỏ đúng Xcode (không dùng mỗi Command Line Tools)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Công cụ sinh project
brew install xcodegen
```

4. Vào thư mục source:

```bash
cd /Users/lucian/Documents/IOS/ThermalControl
```

---

## 2. Build ra file cài (gửi cái này)

```bash
chmod +x Scripts/make_pkg.sh Scripts/postinstall Scripts/install_helper.sh
./Scripts/make_pkg.sh
```

Đợi build **Release** xong. Kết quả:

```text
dist/ThermalControl-1.0.0.pkg    ← gửi file này
dist/ThermalControl-1.0.0.dmg    ← tuỳ chọn
```

### Nên gửi gì?

- **`.pkg`** — người nhận double-click, nhập mật khẩu Mac. App vào `/Applications` **và** cài helper (điều khiển quạt/pin).
- **`.dmg`** — kéo thả app, helper có thể phải cài tay.

---

## 3. Người nhận cài `.pkg`

1. Copy `ThermalControl-1.0.0.pkg` sang máy họ (AirDrop, Drive, USB…).
2. Double-click file `.pkg`.
3. Nếu macOS chặn *nhà phát triển không xác định*:
   - Chuột phải `.pkg` → **Open** → Open  
   - hoặc System Settings → Privacy & Security → **Open Anyway**
4. Next → nhập **mật khẩu máy** (cần quyền admin để cài helper).
5. Mở **Thermal Control** trong Applications.
6. Icon quạt trên thanh menu. Trong app có thể bật **Mở cùng máy**.

Hướng dẫn ngắn cho họ: [docs/CAI_DAT_CHO_NGUOI_DUNG.md](docs/CAI_DAT_CHO_NGUOI_DUNG.md).

---

## 4. Đổi phiên bản trước khi gửi

Sửa `App/Info.plist`:

- `CFBundleShortVersionString` — ví dụ `1.0.1` (tên file pkg lấy số này)
- `CFBundleVersion` — số build, tăng dần (`3`, `4`, …)

Rồi chạy lại:

```bash
./Scripts/make_pkg.sh
```

---

## 5. Script làm gì?

`Scripts/make_pkg.sh`:

1. `xcodegen generate`
2. `xcodebuild -configuration Release`
3. Copy `Thermal Control.app` vào payload `/Applications`
4. `pkgbuild` + `Scripts/postinstall` (cài helper root)
5. Tạo `.dmg` kéo thả

`Scripts/postinstall` chạy lúc cài pkg (quyền root): copy helper vào `/Library/PrivilegedHelperTools/` và `launchctl bootstrap system`.

---

## 6. Lỗi thường gặp khi đóng gói

| Lỗi | Cách xử |
|---|---|
| `xcodebuild` bảo cần Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Signing / Team | Xcode → Settings → Accounts; `DEVELOPMENT_TEAM` trong `project.yml` |
| `xcodegen: command not found` | `brew install xcodegen` |
| Người nhận bị Gatekeeper | Chuột phải → Open. Muốn sạch: Developer ID + notarize (trả phí Apple) |
| App mở nhưng không điều khiển quạt/pin | Cài bằng `.pkg` (có helper). Bản `.dmg` cần chạy `install_helper.sh` |

---

## 7. Notarize (không bắt buộc)

Chữ ký **Apple Development** đủ gửi bạn bè; Gatekeeper sẽ cảnh báo.

Phát hành rộng:

1. Apple Developer Program
2. Developer ID Application + Developer ID Installer
3. Ký rồi:

```bash
xcrun notarytool submit dist/ThermalControl-1.0.0.pkg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple dist/ThermalControl-1.0.0.pkg
```

---

## 8. Gỡ trên máy đã cài

```bash
sudo bash /path/to/ThermalControl/Scripts/uninstall_helper.sh
rm -rf "/Applications/Thermal Control.app"
```
