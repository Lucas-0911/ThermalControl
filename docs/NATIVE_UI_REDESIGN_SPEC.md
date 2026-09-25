# ThermalControl - Native macOS HIG UI Specification (v1.1.0)

## 1. Mục tiêu
Hiện đại hóa toàn diện giao diện Thermal Control theo chuẩn macOS Human Interface Guidelines (macOS Sonoma / Sequoia):
- Menu Bar Extra (Popover): Thiết kế dạng Control Center / Battery native popup:
  - Nền mờ kính native Vibrancy Material (`.ultraThinMaterial` / `.regularMaterial`).
  - Viền hairline tinh tế (`TCTheme.separatorColor`).
  - Bo góc liên tục chuẩn Apple (`continuous` 12pt).
  - Phân nhóm Section rõ ràng, gọn gàng, không dùng khung viền nặng nề.
  - Phông chữ hệ thống, số dạng Monospaced Digit + Rounded Design, biểu tượng SF Symbols chuẩn Apple.
- Controls:
  - Segmented control / Picker phong cách native cho các chế độ Fan (Auto / Quiet / Max / Custom) và Sạc (Đầy 100% / Tùy chỉnh).
  - Input số tối giản, tương tác mượt mà, hỗ trợ bàn phím đầy đủ trong Menu Bar Extra.
- Dashboard:
  - Phong cách macOS System Settings với thanh header mỏng `.bar`, sidebar navigation hoặc form section tinh tế.
  - Thích ứng hoàn hảo Light Mode và Dark Mode.

## 2. Tiêu chí nghiệm thu (Acceptance Criteria)
- [x] Menu Bar Popover có giao diện đồng nhất với Control Center của macOS.
- [x] Hiển thị thông số rõ ràng: Tốc độ quạt, % pin, dòng sạc mA, nhiệt độ CPU/GPU.
- [x] Phản hồi tức thì, animation 60fps mượt mà, không giật lag.
- [x] Tương thích 100% cả Light Mode và Dark Mode.
