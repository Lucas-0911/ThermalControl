# Hướng dẫn build Thermal Control trên Mac

Làm đúng thứ tự. Máy: **Apple Silicon**, macOS 14+.

---

## 0. Chuẩn bị một lần

1. Cài **Xcode** từ App Store.
2. Mở Xcode một lần → Agree → đợi cài thêm components.
3. Xcode → **Settings → Accounts** → thêm Apple ID.
4. Giải nén `ThermalControl.zip` ra ví dụ:

```text
~/Downloads/ThermalControl
```

5. Cài Homebrew nếu chưa có: https://brew.sh  
   Rồi cài XcodeGen:

```bash
brew install xcodegen
```

---

## 1. Sinh file Xcode rồi mở

Mở **Terminal**:

```bash
cd ~/Downloads/ThermalControl
xcodegen generate
open ThermalControl.xcodeproj
```

Trong Xcode phải thấy 2 target:

| Target | Vai trò |
|---|---|
| **ThermalControl** | App menu bar (SwiftUI) |
| **ThermalControlHelper** | Daemon root, ghi SMC |

Không dùng được `xcodegen`: làm tay theo `docs/TAO_PROJECT_XCODE_THU_CONG.md`.

---

## 2. Ký code (bắt buộc)

Làm **cả hai target**.

1. Cột trái bấm icon project **ThermalControl** (xanh).
2. Target **ThermalControl** → tab **Signing & Capabilities**
   - Bật *Automatically manage signing*
   - **Team** = Apple ID của bạn
   - Bundle ID giữ `com.thermalcontrol.app`
   - App Sandbox phải **tắt**
3. Target **ThermalControlHelper**
   - Team giống hệt
   - Bundle ID giữ `com.thermalcontrol.helper`

Nếu Xcode bảo đổi bundle id: **đừng đổi**, trừ khi sửa luôn `Shared/Constants.swift`.

---

## 3. Chọn máy và build

Trên thanh toolbar Xcode:

- Scheme: **ThermalControl**
- Destination: **My Mac** (không chọn simulator)

Build:

```text
Product → Build
phím tắt: ⌘B
```

Thành công = không có lỗi đỏ.

Chạy thử UI (chưa điều khiển quạt/pin được):

```text
Product → Run
phím tắt: ⌘R
```

Icon quạt xuất hiện trên menu bar. Lúc này helper chưa cài → chữ “Chưa kết nối” là bình thường.

---

## 4. Tìm 2 file vừa build

Terminal:

```bash
ls ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/
```

Cần thấy:

- `Thermal Control.app`
- `ThermalControlHelper`

Copy app vào Applications (tuỳ chọn):

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/Thermal\ Control.app /Applications/
```

---

## 5. Cài helper (bắt buộc để điều khiển thật)

Không có bước này thì app **không ghi được SMC**.

```bash
cd ~/Downloads/ThermalControl

HELPER=$(ls -d ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/ThermalControlHelper | head -1)
echo "Helper: $HELPER"

sudo bash Scripts/install_helper.sh "$HELPER"
```

Nhập mật khẩu Mac. Thành công sẽ in:

```text
OK — helper đã cài
```

Kiểm tra daemon:

```bash
launchctl print system/com.thermalcontrol.helper | head -20
cat /tmp/thermalcontrol-helper.log
```

---

## 6. Dùng app

1. Mở **Thermal Control** (Spotlight hoặc `/Applications`).
2. Click icon quạt trên menu bar.
3. Bấm **Kết nối lại**.
4. Chấm xanh + có RPM / % pin = ổn.

Thử an toàn trước:

- Quạt: **System** → **Quiet** (đừng bấm Max ngay)
- Pin (MacBook): **Giữ 70–80**
- Xong việc: **Khôi phục hệ thống**

---

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `xcodegen: command not found` | `brew install xcodegen` |
| Signing failed / Team required | Xcode → Settings → Accounts, chọn Team ở **cả 2 target** |
| File đỏ / không compile | Chạy lại `xcodegen generate`; kiểm tra file vào đúng target |
| App chạy nhưng “chưa kết nối” | Chưa chạy `sudo install_helper.sh` hoặc sai đường dẫn helper |
| `launchctl` bootstrap lỗi | `sudo bash Scripts/uninstall_helper.sh` rồi cài lại |
| Quạt không đổi, log `0x82` | Máy M3/M4 bị `thermalmonitord` chặn; helper sẽ thử `Ftst`. Đợi 5–10 giây rồi Set lại |
| UI không có quạt | Một số Air không quạt, hoặc helper chưa probe — xem log |
| Mac mini không hiện pin | Đúng: máy không có pin nội bộ |

Log khi hỏng:

```bash
cat /tmp/thermalcontrol-helper.log
cat /tmp/thermalcontrol-helper.err
```

---

## Build lại sau khi sửa code

Chỉ sửa UI app → `⌘R` là đủ.

Sửa code **Helper** thì phải cài lại helper:

```bash
sudo bash Scripts/uninstall_helper.sh

HELPER=$(ls -d ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/ThermalControlHelper | head -1)
sudo bash Scripts/install_helper.sh "$HELPER"
```

---

## Gỡ sạch

```bash
sudo bash ~/Downloads/ThermalControl/Scripts/uninstall_helper.sh
rm -rf "/Applications/Thermal Control.app"
```

Quit app trước khi gỡ helper.

---

## Lưu ý

- App **không lên App Store** (cần daemon root).
- Nút “Cài helper” trong UI dùng SMAppService — tài khoản Apple miễn phí hay fail. **Script `sudo` là đường chắc.**
- Ghi SMC không được Apple bảo hành. Đừng kẹp RPM thấp khi máy đang render nặng.
