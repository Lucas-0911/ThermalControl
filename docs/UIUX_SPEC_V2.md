# ThermalControl — Comprehensive UI/UX Design Specification (2026 Edition)
**Tác giả:** An — UI/UX Designer  
**Dự án:** ThermalControl (macOS 14+ Sonoma, macOS 15+ Sequoia)  
**Mục tiêu:** Thiết kế giao diện & trải nghiệm người dùng đẳng cấp, đạt chuẩn Apple Human Interface Guidelines (HIG), mang cảm giác như một tính năng gốc được tích hợp sẵn của macOS (Control Center & System Settings native feel).

---

## 1. UX Research & Hiện Trạng (Pain Points Analysis)

### 1.1. Bối cảnh người dùng
Người dùng ThermalControl là:
1. **Power users, Developers, Creators:** Cần máy chạy hết công suất (Max Fan) khi compile code, render video, hoặc cần không gian yên tĩnh (Quiet Mode) khi họp, thu âm.
2. **MacBook users cắm sạc liên tục (Clamshell mode):** Cần giữ tuổi thọ pin bằng cách hạn chế sạc (Bypass/Limit 70–80%) và theo dõi nguồn điện/nhiệt độ thực tế.
3. **Người dùng phổ thông:** Cần một widget trên Menu Bar hiển thị ngắn gọn thông tin nhiệt độ / quạt / pin mà không gây rối mắt hay làm phân tâm.

### 1.2. Pain Points từ phiên bản cũ (v1.0.0)
| Điểm nghẽn UX cũ | Vấn đề cụ thể | Giải pháp thiết kế mới |
| :--- | :--- | :--- |
| **Menu Bar Extra dùng `GroupBox`** | `GroupBox` của macOS có viền gồ ghề, cổ điển, không ăn nhập với phong cách kính mờ Vibrancy của macOS Sonoma/Sequoia. | Chuyển sang kiến trúc **Vibrancy Glass Card (`.regularMaterial` / `.thinMaterial`)**, bo góc liên tục `12pt`, loại bỏ viền dày, thay bằng Hairline Stroke `0.5pt separatorColor`. |
| **Phân cấp thông tin phân mảnh** | Tốc độ quạt, % pin và nhiệt độ hiển thị rời rạc, thiếu 1 cái nhìn tổng quan "At a Glance" nhanh chóng. | Thiết kế **Hero Status Bar** ở đầu Popover: Gộp 3 chỉ số chính (Nhiệt độ cao nhất CPU/GPU, Tốc độ quạt tổng thể, Trạng thái pin/nguồn) thành một thanh Glanceable bar tinh gọn. |
| **Thanh trượt & Input RPM** | Nhập RPM bằng bàn phím đôi khi bất tiện nếu chỉ muốn điều chỉnh nhanh khi dùng chuột/trackpad. | Bổ sung **Adaptive Quick Slider + Preset Stepper (±100 RPM)** kèm haptic feedback trực quan trên UI. Giữ ô số monospaced trực tiếp. |
| **Quản lý giới hạn pin phức tạp** | Có 2 ô Min và Max kèm nút Apply, dễ gây nhầm lẫn nếu người dùng không hiểu cơ chế duy trì pin. | Đổi thành **Smart Charge Limiter Slider / Segmented Presets (80% Balanced, 100% Full, Custom Range)** với chú thích visual giải thích rõ: "Dừng sạc ở X%, sạc lại khi dưới Y%". |
| **Main Window Dashboard cồng kềnh** | Giao diện cửa sổ chính mở rộng ngang lớn (820px) nhưng bố cục dạng card đơn điệu, chưa tận dụng tốt phân khu 2 cột tiêu chuẩn của macOS Settings. | Tái cấu trúc Dashboard theo chuẩn **macOS Split-View Navigation** (hoặc Unified Modern Canvas) với Sidebar phân loại: *Overview*, *Fan Curves & Control*, *Battery Health & Power*, *Sensors Telemetry*, *Settings & Helper*. |
| **Hiển thị Helper Status** | Khi helper mất kết nối hoặc cần duyệt quyền, thông báo chiếm diện tích hoặc nút bấm chưa đủ thu hút hành động (Call To Action). | Thiết kế **Status Banner thông minh**: Tự thu gọn thành một chấm nhỏ (Subtle Accent Dot) khi bình thường, và mở rộng thành Banner cảnh báo hướng dẫn từng bước (Step-by-step guidance) khi cần cấp quyền. |

---

## 2. Design System & Tokens (Apple HIG Standard)

### 2.1. Dynamic Semantic Palette
Không sử dụng màu cứng (hardcoded HEX), toàn bộ hệ màu thích ứng 100% với Dynamic System Colors và Accent Color của hệ điều hành:

| Token Name | Light Mode (AppKit) | Dark Mode (AppKit) | Mục đích / Ngữ cảnh sử dụng |
| :--- | :--- | :--- | :--- |
| `TCColors.fan` | `.systemBlue` | `.systemBlue` | Trạng thái quạt, tốc độ RPM, biểu tượng Fan |
| `TCColors.fanQuiet` | `.systemPurple` | `.systemPurple` | Chế độ Quiet, êm ái ban đêm |
| `TCColors.fanMax` | `.systemRed` | `.systemRed` | Chế độ Max, tản nhiệt tối đa |
| `TCColors.battery` | `.systemGreen` | `.systemGreen` | Trạng thái pin khỏe, đang sạc bình thường |
| `TCColors.chargeInhibit` | `.systemIndigo` / `.systemTeal` | `.systemTeal` | Đang ngắt sạc (Bypass/Limit active) |
| `TCColors.power` | `.systemYellow` / `.systemOrange`| `.systemYellow` | Công suất Watt, điện áp, adapter |
| `TCColors.tempNormal` | `.systemTeal` (<65°C) | `.systemTeal` (<65°C) | Nhiệt độ mát mẻ |
| `TCColors.tempWarm` | `.systemYellow` (65–79°C) | `.systemYellow` | Nhiệt độ tải vừa |
| `TCColors.tempHot` | `.systemOrange` (80–94°C) | `.systemOrange` | Nhiệt độ tải nặng |
| `TCColors.tempCritical`| `.systemRed` (≥95°C) | `.systemRed` | Cảnh báo nhiệt độ đỉnh |

### 2.2. Surface & Materials
- **Popover Background:** `Material.ultraThinMaterial` kết hợp `Color(nsColor: .windowBackgroundColor).opacity(0.85)`.
- **Card Background:** `Material.regularMaterial` kết hợp `.background(Color(nsColor: .controlBackgroundColor).opacity(0.6))`.
- **Active / Hover State:** `Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)`.
- **Borders / Separators:** `Color(nsColor: .separatorColor).opacity(0.4)`, độ dày `0.5pt` (Hairline crispness).
- **Corner Radii:**
  - Micro-controls (Buttons, Steppers): `6pt` continuous (`DS.Radius.control`).
  - Textfields / Inputs: `8pt` continuous (`DS.Radius.field`).
  - Inner Cards / Tiles: `10pt` continuous (`DS.Radius.card`).
  - Outer Cards / Popover container: `12pt` continuous (`DS.Radius.panel`).

### 2.3. Typography & Monospacing
- **Tiêu đề Section:** `.system(size: 11, weight: .semibold, design: .default)` với `.foregroundStyle(.secondary)` và uppercase tracking `0.6pt` (Ví dụ: `QUẠT TẢN NHIỆT`, `QUẢN LÝ PIN`).
- **Metric Big Numbers:** `.system(size: 26, weight: .bold, design: .rounded)` đi kèm `.monospacedDigit()` để số không bị nhảy vị trí khi RPM hoặc % pin thay đổi.
- **Metric Unit:** `.system(size: 11, weight: .medium, design: .rounded)` với `.foregroundStyle(.tertiary)`.
- **Body & Labels:** `.system(size: 13, weight: .regular)` chuẩn San Francisco.
- **Footnotes & Hints:** `.system(size: 11, weight: .regular)` với màu `.secondaryLabel`.

---

## 3. Kiến Trúc Giao Diện 1: Menu Bar Popover (Trải nghiệm chính)

Khung kích thước chuẩn: **Width 350pt**, chiều cao tự co giãn linh hoạt (Dynamic Height từ 320pt đến 480pt tùy theo cấu hình phần cứng).

```
+-----------------------------------------------------------+
| [fanblades.fill] ThermalControl  ● Connected    [⚙]  [✕]  |  <- Header Bar
+-----------------------------------------------------------+
|  [ 54°C CPU ]    |    [ 2,150 RPM ]    |   [ 80% Plugged ]|  <- Glanceable Hero Metric
+-----------------------------------------------------------+
| FAN CONTROL                                               |
|  +-----------------------------------------------------+  |
|  |   ( ( 🌀 2150 RPM ) )          ( ( 🌀 2180 RPM ) )  |  |  <- Fan Radial Gauges
|  |         Quạt Trái                    Quạt Phải      |  |
|  |  +-----------------------------------------------+  |  |
|  |  |   Auto   |   Quiet   |   Max   |    Custom    |  |  |  <- Segmented Mode Switcher
|  |  +-----------------------------------------------+  |  |
|  |  [⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯]  |  |  <- Quick RPM Slider
|  |  Tốc độ đặt: [ 2200 ] RPM        [ -100 ]  [ +100 ]  |  |  <- Precise Stepper Input
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
| BATTERY & POWER                                           |
|  +-----------------------------------------------------+  |
|  | [⚡] 80% — Đang giữ mức sạc (Bypass)        35W In   |  |  <- Battery Status Bar
|  | [========================-----------------]            |  |  <- Battery Capacity Bar
|  |  Mode: [ Sạc đầy (100%) ]  [ Giới hạn sạc (80%) ]   |  |  <- Quick Charge Mode
|  |  Ngưỡng: Dừng ở [ 80% ] · Sạc lại khi dưới [ 75% ]     |  |  <- Inline Range Config
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
| SENSORS SNAPSHOT                                          |
|  +-----------------------------------------------------+  |
|  | CPU Efficiency: 48°C [====----] GPU Core: 52°C [===--] |  |  <- Mini Spark Bars
|  | CPU Perform.:  56°C [======--] Vỏ máy:   38°C [==----] |  |
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
```

### Chi tiết tương tác từng phần trong Menu Bar Popover:

#### 3.1. Header Bar
- **App Identity:** Icon quạt màu xanh Apple (`TCColors.fan`) + Tên ứng dụng `ThermalControl` kèm số phiên bản nhỏ.
- **Trạng thái kết nối Helper:** 
  - Đã kết nối: Chấm tròn xanh lá 6pt thở nhẹ (pulsing breathing animation nếu đang cập nhật) + tooltip "Helper hoạt động bình thường".
  - Mất kết nối / Cần quyền: Chấm cam/đỏ kèm nút bấm nhỏ `Cấp quyền` mở ngay hướng dẫn.
- **Action Icons:** 
  - Nút bánh răng `gearshape` (24x24pt circular hover button) mở Cửa sổ Dashboard chi tiết.
  - Nút thoát `xmark` thu nhỏ, tooltip rõ ràng.

#### 3.2. Glanceable Hero Metric
- Một hàng ngang chia 3 cột thẻ nhỏ (Mini Metric Pills) với hiệu ứng kính mờ:
  1. **Nhiệt độ đỉnh:** Hiển thị nhiệt độ cao nhất hiện tại (ví dụ: `54°C`), đổi màu gradient theo mức nhiệt (Xanh lơ → Vàng → Cam → Đỏ).
  2. **Tốc độ Quạt:** Trung bình hoặc quạt cao nhất hiện tại (ví dụ: `2,150 RPM`), icon cánh quạt xoay tỉ lệ theo tốc độ thực.
  3. **Pin & Nguồn:** `% Pin` + icon sạc/ngắt sạc + công suất sạc vào Watt (ví dụ: `80% · 35W`).

#### 3.3. Fan Control Card (Thẻ Quạt)
- **Fan Radial Gauge:**
  - Thiết kế vòng tròn mở góc (Arc Gauge) thanh mảnh hơn bản cũ, đường nét 8pt bo tròn đầu mút (`lineCap: .round`).
  - Biểu tượng quạt ở tâm xoay mượt mà bằng `TimelineView` (thuật toán quán tính vật lý theo RPM thực, dừng êm khi 0 RPM).
  - Tự động hiển thị 1 quạt (MacBook Air/Pro 13/14) hoặc 2 quạt (MacBook Pro 16) một cách đối xứng hoàn hảo.
- **Segmented Mode Selector:**
  - 4 chế độ: `Auto` (Hệ thống Apple tự quản), `Quiet` (Êm ái, giới hạn RPM thấp), `Max` (Quạt tối đa, làm mát khẩn cấp), `Custom` (Tự chỉnh).
  - Trạng thái Active có nền đổ bóng nhẹ chuẩn macOS Segmented Control (Smooth Sliding Pill).
- **Điều khiển Custom RPM tiện lợi:**
  - Khi chọn `Custom`, thanh trượt RPM mượt mà xuất hiện với animation trượt xuống (`.transition(.move(edge: .top).combined(with: .opacity))`).
  - Người dùng có thể kéo Slider hoặc bấm nút nhanh `-100 RPM` / `+100 RPM` để vi chỉnh mà không bắt buộc phải gõ bàn phím.
  - Ô số RPM hỗ trợ gõ trực tiếp số mong muốn và nhấn `Enter` hoặc click ra ngoài để xác nhận ngay.

#### 3.4. Battery & Power Card (Thẻ Pin & Nguồn)
- **Chỉ số năng lượng trực quan:**
  - Thanh trạng thái pin có dải gradient năng lượng (Xanh lá khi bình thường, Cam khi đang xả, Xanh tím khi đang Inhibit/Bypass).
  - Hiển thị dòng điện rõ ràng: `Nguồn vào: 65W (Adapter 96W)` hoặc `Đang xả: -12W`.
- **Nút chuyển đổi chế độ sạc nhanh:**
  - `Sạc đầy (100%)`: Chế độ mặc định của macOS.
  - `Giới hạn (Bảo vệ pin)`: Tự động kích hoạt cơ chế ngắt sạc khi pin đạt ngưỡng (Mặc định: Dừng ở 80%, sạc lại khi xuống dưới 75%).
  - Người dùng có thể kéo hoặc chỉnh nhanh 2 mốc Min/Max trực tiếp với cảnh báo hợp lệ (Min luôn < Max).

#### 3.5. Sensors Snapshot Card (Thẻ Nhiệt Độ Rút Gọn)
- Hiển thị 4 cảm biến trọng yếu nhất (CPU Performance, CPU Efficiency, GPU Core, Vỏ máy Skin).
- Mỗi cảm biến có thanh đo Mini Bar gọn gàng với màu sắc phản ánh chính xác trạng thái nhiệt (Mát, Ấm, Nóng).

---

## 4. Kiến Trúc Giao Diện 2: Main Window Dashboard (Trung Tâm Điều Khiển)

Kích thước cửa sổ mặc định: **920pt x 640pt** (Hỗ trợ resize linh hoạt, chuẩn macOS NavigationSplitView).

```
+----------------------------------------------------------------------------------------------------+
|  [Sidebar Toggle]  ThermalControl  —  System Telemetry & Controls                   [Help] [Reset] |
+-----------------------+----------------------------------------------------------------------------+
|  NAVIGATION           |  OVERVIEW & METRICS                                                        |
|                       |  +----------------------------------------------------------------------+  |
|  📊 Tổng quan (Overview)|  | [ 54°C CPU ]    [ 2150 RPM ]     [ 80% Pin ]      [ 35W Power In ]   |  |
|  🌀 Điều khiển Quạt   |  +----------------------------------------------------------------------+  |
|  🔋 Pin & Nguồn điện  |                                                                            |
|  🌡️ Cảm biến Nhiệt độ |  QUẠT HOẠT ĐỘNG (FANS)                                                     |
|  ⚙️ Cài đặt & Helper  |  +----------------------------------------------------------------------+  |
|                       |  |  +-----------------------------+     +-----------------------------+ |  |
|                       |  |  | Fan 1 (Trái): 2150 RPM      |     | Fan 2 (Phải): 2180 RPM      | |  |
|                       |  |  | ( ( 🌀 Gauge lớn ) )        |     | ( ( 🌀 Gauge lớn ) )        | |  |
|                       |  |  +-----------------------------+     +-----------------------------+ |  |
|                       |  |  Chế độ: [ Auto ]  [ Quiet ]  [ Max ]  [ Custom ]                    |  |
|                       |  +----------------------------------------------------------------------+  |
|                       |                                                                            |
|                       |  BIỂU ĐỒ NĂNG LƯỢNG & CÔNG SUẤT (30 GIÂY GẦN NHẤT)                        |
|                       |  +----------------------------------------------------------------------+  |
|                       |  |  [~~~~~~~~ Biểu đồ Swift Charts công suất sóng mượt mà ~~~~~~~~~]    |  |
|                       |  +----------------------------------------------------------------------+  |
+-----------------------+----------------------------------------------------------------------------+
```

### Các phân trang chi tiết trong Main Window:

### 4.1. Trang "Tổng quan" (Overview)
- **Top Metrics Row:** 4 Card thống kê lớn với icon nổi bật, chữ số `32pt Rounded Bold`:
  1. *Nhiệt độ đỉnh*: Tên cảm biến nóng nhất + nhiệt độ (°C).
  2. *Quạt*: Tốc độ trung bình / Tình trạng chế độ đang chạy.
  3. *Pin*: Phần trăm pin + Trạng thái (Đang sạc, Đã sạc đầy, Giữ sạc, Đang dùng pin).
  4. *Nguồn*: Công suất tiêu thụ hiện tại (Watts) + Loại nguồn (Adapter / Battery).
- **Bộ đôi điều khiển nhanh:** Bản sao mở rộng của Fan Panel và Battery Panel với diện tích thao tác rộng rãi.
- **Live Power Chart:** Biểu đồ sóng `Swift Charts` hiển thị công suất dòng điện theo thời gian thực (30 giây gần nhất) với hiệu ứng Gradient đổ bóng lung linh.

### 4.2. Trang "Điều khiển Quạt" (Fan Curves & Manual Control)
- Hiển thị danh sách từng quạt độc lập (Fan 1, Fan 2,...):
  - Cho phép điều khiển **Đồng bộ cả hai quạt (Sync)** hoặc **Điều khiển riêng lẻ từng quạt (Independent control)** cho người dùng nâng cao.
  - Hiển thị dải RPM cho phép từ phần cứng SMC (`Min RPM` đến `Max RPM`).
  - Thước đo thanh trượt trực quan với các mốc đánh dấu (25%, 50%, 75%, 100%).
  - Chức năng an toàn: Khi nhiệt độ phần cứng vượt quá 95°C, hệ thống hiển thị cảnh báo và tự động vô hiệu hóa chế độ Quiet để bảo vệ linh kiện.

### 4.3. Trang "Pin & Nguồn điện" (Battery Health & Inhibit)
- Thống kê chi tiết phần cứng pin (đọc từ SMC & IOKit):
  - Số chu kỳ sạc (Cycle Count).
  - Độ chai pin / Dung lượng tối đa (Health %).
  - Nhiệt độ pin hiện tại.
  - Điện áp từng cell (Cell Voltage) và cường độ dòng sạc thực tế (mA).
- **Cơ chế Duy trì Pin (Battery Maintainer):**
  - Giải thích trực quan bằng sơ đồ luồng điện:
    `Nguồn sạc (Adapter) ➔ [Bypass Switch] ➔ Nuôi bo mạch (Bảo vệ pin không bị nhồi xả liên tục)`.
  - Cấu hình ngưỡng bảo vệ: Slider 2 đầu (Range Slider) từ 50% đến 90%.
  - Chức năng chuyên sâu: "Xả pin cưỡng bức (Force Discharge)" có nhãn cảnh báo đỏ nổi bật, chỉ dùng khi cần hiệu chuẩn (calibrate) pin.

### 4.4. Trang "Cảm biến Nhiệt độ" (Sensors Telemetry)
- Danh sách toàn bộ cảm biến đọc được từ máy Mac (CPU P-Cores, CPU E-Cores, GPU Die, NPU Neural Engine, Vỏ máy, Ổ cứng SSD, v.v.).
- Tìm kiếm & Lọc cảm biến theo nhóm (CPU, GPU, Battery, System).
- Hiển thị theo 2 chế độ:
  - **Grid View:** Dạng thẻ trực quan, mỗi thẻ có thanh đo nhiệt độ và biểu đồ xu hướng.
  - **Table View:** Dạng bảng số liệu chi tiết, sắp xếp tăng dần / giảm dần theo nhiệt độ.

### 4.5. Trang "Cài đặt & Trợ lý Helper" (Settings & Service)
- **Tùy chọn Khởi động:**
  - Bật/tắt "Khởi động cùng macOS" (Launch at Login via `SMAppService.mainApp`).
  - Tùy chọn hiển thị icon Menu Bar: Chỉ hiện Icon / Hiện kèm Nhiệt độ / Hiện kèm Tốc độ quạt / Hiện kèm % Pin.
- **Ngôn ngữ:** Chuyển đổi mượt mà giữa Tiếng Việt, Tiếng Anh, hoặc Theo hệ thống.
- **Trạng thái Helper Tool:**
  - Hiển thị phiên bản Helper hiện tại và trạng thái chạy nền.
  - Nút kiểm tra kết nối lại XPC (`Reconnect`).
  - Nút đặt lại cài đặt gốc (`Restore System Control`).

---

## 5. Micro-interactions, Motion & UX Polish

1. **Hiệu ứng Quạt xoay quán tính (Realistic Inertia Spin):**
   - Không dùng animation lặp cố định thô cứng. Biểu tượng quạt quay mượt mà dựa trên tốc độ RPM thực: khi chuyển từ 2000 RPM lên 5000 RPM, quạt tăng tốc từ từ; khi tắt về 0 RPM, quạt giảm tốc dần theo lực quán tính vật lý (exponential decay).
2. **Smooth Value Transitions (Number Morphing):**
   - Số nhiệt độ và RPM khi thay đổi sẽ dùng hiệu ứng `.contentTransition(.numericText())` của SwiftUI (iOS 16+ / macOS 13+), tạo hiệu ứng trượt số tự nhiên như ứng dụng Clock/Weather của Apple.
3. **Responsive Visual Feedback:**
   - Khi click chọn chế độ quạt hoặc sạc, nút có phản hồi tức thì với animation `.spring(response: 0.3, dampingFraction: 0.7)`.
4. **Trực quan hóa trạng thái sạc (Pulsing Bolt):**
   - Khi đang cắm sạc công suất cao (>30W), biểu tượng tia sét có hiệu ứng phát sáng nhẹ (subtle glow). Khi đang ở chế độ Ngắt sạc (Bypass), biểu tượng chuyển sang khiên chắn hoặc tia sét đứt đoạn (`bolt.slash`).
5. **Thông báo lỗi không xâm lấn (Non-intrusive Inline Alerts):**
   - Không pop up cửa sổ cảnh báo làm gián đoạn người dùng nếu không nguy cấp. Lỗi XPC hoặc Helper được hiển thị dưới dạng Inline Banner có thể bấm để xem chi tiết hoặc thử lại.

---

## 6. Lộ trình triển khai & Phân công kỹ thuật (Implementation Plan)

| Giai đoạn | Nội dung công việc | Nhân sự phụ trách |
| :--- | :--- | :--- |
| **Giai đoạn 1: Design Tokens & Base Components** | - Tối ưu `DesignTokens.swift` và `TCTheme.swift`.<br>- Xây dựng các component mới: `HeroGlanceBar`, `AdaptiveSlider`, `SmoothArcGauge`, `SensorsGridView`. | **An (UI/UX)** + **Mai (iOS UI)** |
| **Giai đoạn 2: Redesign Menu Bar Popover** | - Tái cấu trúc `MenuBarView.swift` theo layout Popover Glass mới.<br>- Tích hợp Stepper RPM & Quick Modes.<br>- Tinh chỉnh animation xoay quạt và numeric text transition. | **Mai (iOS UI)** |
| **Giai đoạn 3: Redesign Main Dashboard Window** | - Tái cấu trúc `DashboardView.swift` với Split Navigation.<br>- Xây dựng các trang: Overview, Fan Curves, Battery Health, Sensors Telemetry, Settings.<br>- Tích hợp `Swift Charts` mượt mà cho công suất & nhiệt độ. | **Mai (iOS UI)** + **Tuấn (iOS Core)** |
| **Giai đoạn 4: Quality Control & Design Audit** | - Kiểm tra pixel-perfect chuẩn Apple HIG trên cả Light Mode và Dark Mode.<br>- Kiểm tra responsive khi mở rộng cửa sổ và thay đổi độ phân giải màn hình (Retina / Non-Retina).<br>- Test hiệu năng CPU/GPU không tăng khi render animation TimelineView. | **Trâm (QC)** + **An (UI/UX)** |
| **Giai đoạn 5: Packaging & Release** | - Build bản cập nhật, kiểm tra notarization & helper service.<br>- Đóng gói PKG/DMG bản release UI mới. | **Nam (DevOps)** |

---

## 7. Kết luận
Bản thiết kế này biến **ThermalControl** từ một tiện ích điều khiển đơn thuần thành một trải nghiệm phần mềm cao cấp, tinh tế và chuẩn mực bậc nhất trên macOS. Người dùng vừa có được sự tiện lợi tức thì tại Menu Bar, vừa có đầy đủ công cụ chuyên sâu tại Dashboard cửa sổ lớn mà vẫn giữ trọn vẹn nét thanh lịch của hệ điều hành Mac.
