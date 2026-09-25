# Thermal Control (macOS)

[![macOS Sonoma / Sequoia](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/badge/Release-v1.0.0-brightgreen)](https://github.com/Lucas-0911/ThermalControl/releases)

**Thermal Control** là ứng dụng mã nguồn mở trên macOS (chạy trên Menu Bar và Dashboard), cho phép người dùng kiểm soát toàn diện:
- 🌀 **Tốc độ quạt tản nhiệt (Fan Speed Control)**: Chế độ Hệ thống (Auto / System), Êm ái (Quiet), Tối đa (Max) hoặc Tuỳ chỉnh chính xác theo RPM.
- 🔋 **Giới hạn sạc pin phần cứng (SMC Battery Charge Inhibit)**: Ngắt sạc trực tiếp qua Apple SMC Tahoe / M-Series (Apple Silicon M1/M2/M3/M4 & Intel), giữ pin ở mức 80% hoặc tùy chỉnh để tối đa tuổi thọ pin khi cắm sạc liên tục.
- ⚡ **Theo dõi công suất & nhiệt độ theo thời gian thực**: Đo dòng điện, công suất adapter / battery drain (W) kèm biểu đồ sparkline 30s và cảm biến nhiệt độ CPU/GPU.
- 🎨 **Giao diện chuẩn macOS Human Interface Guidelines (HIG)**: Thiết kế dạng popover Control Center mờ kính (vibrancy material), bo góc continuous 12pt, hỗ trợ đầy đủ Dark Mode & Light Mode.

---

## 📥 Tải về & Cài đặt (Dành cho người dùng)

Bạn có thể tải ngay bộ cài đóng gói sẵn tại thư mục [`dist/`](dist/) hoặc tab [Releases](https://github.com/Lucas-0911/ThermalControl/releases):

| Định dạng file | Hướng dẫn cài đặt | Khuyến nghị |
|---|---|---|
| **`ThermalControl-1.0.0.pkg`** | Nhấp đúp chuột vào file `.pkg`, nhấn Tiếp tục và nhập mật khẩu máy để cài đặt App + Privileged Helper tự động. | **Khuyên dùng** ⭐️ |
| **`ThermalControl-1.0.0.dmg`** | Mở file `.dmg`, kéo `Thermal Control.app` vào thư mục `Applications`. | Tiện lợi |

> **Lưu ý quan trọng sau khi cài đặt:**
> 1. Vào **System Settings (Cài đặt hệ thống) → General (Cài đặt chung) → Login Items (Mục đăng nhập)**.
> 2. Bật cho phép **Thermal Control** chạy ngầm (`Allow in the Background`) để Privileged Helper có quyền giao tiếp SMC.

---

## ✨ Tính năng nổi bật

- **Quạt thông minh**:
  - `Auto`: Trả lại quyền điều khiển tự động cho hệ điều hành macOS.
  - `Quiet`: Duy trì mức quạt êm ái khi làm việc văn phòng.
  - `Max`: Đẩy tốc độ quạt tối đa khi render đồ hoạ, biên dịch code, train AI.
  - `Custom`: Đặt mức RPM mong muốn cho từng quạt riêng biệt (hệ thống tự động lưu cấu hình).
- **Bảo vệ pin chuyên sâu**:
  - Cơ chế **Direct SMC Write** can thiệp thanh ghi `CHTE` / `CHIE` ngắt dòng sạc hoàn toàn về **0 mA** khi đạt ngưỡng thiết lập.
  - Tự động xả tải và bảo vệ chống chai pin khi cắm sạc qua đêm hoặc dùng màn hình ngoài (Thunderbolt/Type-C).
- **An toàn tuyệt đối (Safety Watchdog)**:
  - Tự động kích hoạt quạt tối đa nếu CPU vượt ngưỡng 100°C.
  - Watchdog heartbeat 45 giây: Nếu app bị tắt đột ngột, daemon helper sẽ tự động hoàn trả quyền điều khiển quạt về hệ thống.

---

## 🛠️ Dành cho lập trình viên (Developer Guide)

### Yêu cầu môi trường:
- macOS 14.0 (Sonoma) hoặc mới hơn
- Xcode 15.0+ hoặc Xcode 16.0+
- `xcodegen` (`brew install xcodegen`)

### Biên dịch & Chạy thử:

```bash
# 1. Clone repository
git clone https://github.com/Lucas-0911/ThermalControl.git
cd ThermalControl

# 2. Sinh project Xcode
xcodegen generate

# 3. Mở dự án trong Xcode
open ThermalControl.xcodeproj
```

Chọn scheme **ThermalControl**, chọn destination **My Mac** và nhấn `Cmd + R` để chạy.

### Đóng gói bộ cài (`.pkg` và `.dmg`):

Chạy script đóng gói tự động:
```bash
chmod +x Scripts/make_pkg.sh
./Scripts/make_pkg.sh
```
File đóng gói hoàn chỉnh sẽ xuất hiện trong thư mục `dist/`.

---

## 📂 Cấu trúc dự án

```
ThermalControl/
├── App/                # Mã nguồn giao diện SwiftUI, MenuBar, Dashboard, Assets
│   ├── Views/          # MenuBarView, DashboardView, Theme, Custom Components
│   └── ViewModels/     # ThermalViewModel, FanViewModel, BatteryViewModel
├── Helper/             # Privileged Root Daemon điều khiển SMC qua IOKit & XPC
│   ├── SMC/            # SMC IOKit Driver, Tahoe SMC Charge Controller
│   └── Safety/         # SafetyWatchdog giám sát nhiệt độ phần cứng
├── Shared/             # Giao thức XPC chung, Model, SMC Keys, Constants
├── Scripts/            # Script cài đặt helper, đóng gói .pkg & .dmg
└── dist/               # File phát hành cài đặt (ThermalControl.pkg, .dmg)
```

---

## 📄 Bản quyền (License)

Dự án được phân phối dưới giấy phép **MIT License**. Mọi người đều có thể tự do sử dụng, chỉnh sửa và đóng góp mã nguồn.
