# UI/UX — Thermal Control

Tài liệu chi tiết bản nâng cấp 2026: xem file [`docs/UIUX_SPEC_V2.md`](docs/UIUX_SPEC_V2.md).

## Tóm tắt định hướng thiết kế mới (Apple HIG 2026):

1. **Menu Bar Popover (Trải nghiệm tức thì - 350pt):**
   - Nền kính mờ Vibrancy (`.regularMaterial` / `.ultraThinMaterial`), bo góc chuẩn `12pt continuous`.
   - **Hero Glance Bar**: Xem nhanh cùng lúc 3 chỉ số đỉnh (Nhiệt độ nóng nhất, Tốc độ quạt tổng thể, Tình trạng sạc & công suất Watt).
   - **Fan Control Card**: Radial Arc Gauge xoay mượt mà theo quán tính vật lý thực, Segmented Mode (Auto, Quiet, Max, Custom), Quick Slider + Stepper (±100 RPM) và ô số monospaced trực tiếp.
   - **Battery & Power Card**: Trực quan hóa chế độ sạc (Full 100% vs Giới hạn 70-80% duy trì pin/bypass), theo dõi dòng điện In/Out và công suất adapter.
   - **Sensors Snapshot**: Hiển thị mini bar các cảm biến trọng yếu (CPU, GPU, Skin) với màu sắc chuyển đổi linh hoạt theo mức nhiệt.

2. **Main Window Dashboard (Trung tâm kiểm soát chuyên sâu - Split View Navigation):**
   - Sidebar tiêu chuẩn macOS: Overview, Fan Control, Battery Health, Sensors Telemetry, Settings & Helper.
   - Thống kê chi tiết phần cứng SMC, đồ thị Swift Charts công suất sóng thời gian thực.
   - Quản lý độc lập từng quạt hoặc đồng bộ.

3. **Design System & Microcopy:**
   - 100% Dynamic System Colors, thích ứng Light/Dark Mode và System Accent Color.
   - Số học dạng Monospaced Rounded Digit, animation `.contentTransition(.numericText())` mượt mà.
   - Bản ngữ hóa hoàn chỉnh Tiếng Việt và Tiếng Anh.
