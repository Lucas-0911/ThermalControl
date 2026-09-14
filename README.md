# Thermal Control

App macOS trên thanh menu: điều khiển **quạt**, **giới hạn sạc pin**, xem **nhiệt** và **công suất nguồn**.

> macOS **không dùng `.dpkg`** (gói Debian/Linux).  
> File gửi người khác là **`.pkg`** (cài đặt) hoặc **`.dmg`** (kéo thả).

---

## Tính năng

- Quạt: Auto / Êm / Max / Custom (nhớ RPM custom)
- Pin: sạc full hoặc dừng ở % tự chọn
- Biểu đồ nguồn ~30 giây
- Nhiệt CPU / GPU
- Tiếng Việt + English (theo máy, hoặc chọn trong app)
- Mở cùng máy (login item)
- Helper root ghi SMC (cần mật khẩu lúc cài)

**Yêu cầu:** macOS 14+, Xcode nếu tự build. MacBook mới có pin + quạt.

---

## Tài liệu

| File | Nội dung |
|---|---|
| [HUONG_DAN_DONG_GOI.md](HUONG_DAN_DONG_GOI.md) | **Build `.pkg` / `.dmg` để gửi người khác** |
| [docs/CAI_DAT_CHO_NGUOI_DUNG.md](docs/CAI_DAT_CHO_NGUOI_DUNG.md) | Người nhận cài app thế nào |
| [HUONG_DAN_BUILD.md](HUONG_DAN_BUILD.md) | Build & chạy lúc dev (Xcode) |
| [TINH_NANG.md](TINH_NANG.md) | Đặc tả tính năng |
| [UIUX.md](UIUX.md) | Ghi chú UI |

---

## Gửi cho mọi người (một lệnh)

Máy bạn cần Xcode đầy đủ + `xcodegen`:

```bash
brew install xcodegen
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

cd /đường/dẫn/ThermalControl
chmod +x Scripts/make_pkg.sh Scripts/postinstall Scripts/install_helper.sh
./Scripts/make_pkg.sh
```

Ra file trong `dist/`:

| File | Gửi cái này |
|---|---|
| `ThermalControl-1.0.0.pkg` | **Nên gửi.** Double-click, nhập mật khẩu máy, xong. |
| `ThermalControl-1.0.0.dmg` | Kéo app vào Applications; helper cài thêm nếu thiếu. |

Chi tiết: **[HUONG_DAN_DONG_GOI.md](HUONG_DAN_DONG_GOI.md)**.

---

## Dev — chạy trên máy mình

```bash
brew install xcodegen
cd ThermalControl
xcodegen generate
open ThermalControl.xcodeproj
```

- Scheme **ThermalControl**, destination **My Mac**
- Signing: Team Apple ID cho **cả 2 target**
- `⌘R` chạy UI

Cài helper để điều khiển thật:

```bash
HELPER=$(ls -d ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/ThermalControlHelper | head -1)
sudo bash Scripts/install_helper.sh "$HELPER"
```

---

## Cấu trúc

```
App/          SwiftUI app, localization en/vi, icon
Helper/       Daemon root (SMC quạt + pin)
Shared/       Protocol XPC, model, SMC
Scripts/      install helper, đóng gói pkg/dmg
docs/         hướng dẫn thêm
```

---

## Gỡ

```bash
sudo bash Scripts/uninstall_helper.sh
rm -rf "/Applications/Thermal Control.app"
```

---

## Lưu ý

Ghi SMC không được Apple bảo hành. Đừng kẹp quạt thấp khi máy đang tải nặng. App không lên App Store vì cần helper root.
