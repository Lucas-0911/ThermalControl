# Kiến trúc Thermal Control

## Phạm vi

Thermal Control là app macOS 14+ viết bằng SwiftUI. App chạy không đặc quyền; helper LaunchDaemon là writer duy nhất của AppleSMC.

```text
SwiftUI Views
  → ThermalViewModel + Fan/Battery/Power view models
  → XPCClient
  → ThermalControlHelper (root LaunchDaemon)
  → FanController / BatteryController / SafetyWatchdog
  → SMCService / AppleSMC
```

## Ranh giới

- `App/`: UI, intent người dùng, trạng thái hiển thị, telemetry local read-only và cài/kết nối helper.
- `Helper/`: policy quạt/pin, SMC writes, persistence, sleep/wake và fail-safe.
- `Shared/`: DTO `NSSecureCoding`, XPC protocol, SMC primitives, safety seams dùng bởi cả app/helper/tests.
- `Tests/`: app-hosted tests cho view model/lifecycle; hostless helper tests cho controller.
- `Scripts/`: build package và cài/gỡ LaunchDaemon.

View không gọi IOKit, XPC hoặc `SMAppService`. App không ghi SMC. Helper không import SwiftUI.

## Lifecycle và polling

- Heartbeat app: 5 giây; helper fail-safe timeout: 15 giây.
- Telemetry: dashboard 2 giây, menu 2,5 giây, background 15 giây.
- Power history 1 Hz chỉ khi dashboard visible.
- `ThermalSession` sở hữu timer và workspace observers, có start/stop/pause/resume rõ ràng; visibility theo occlusion/minimize cửa sổ, không chỉ view appearance.
- Refresh và local sensor reads là single-flight/coalesced; generation loại completion cũ, kể cả Restore sau sleep/disconnect.
- XPC reply resolve một lần khi reply/timeout/cancel/invalidate; cancel chỉ dừng local wait, không thu hồi hardware write đã gửi.
- Fan command và battery command được serialize trong từng tính năng; chỉnh số chỉ tạo draft, Apply/Cancel tường minh. Quick mode áp ngay nhưng chỉ persist sau readback; saved draft không thay actual RPM.
- Helper registration/install chỉ từ thao tác người dùng, không tự bật authorization từ launch/refresh. Protocol hiện tại3, helper1.3.0; helper cũ bị khóa controls, không tự migration.
- Native XPC peer code-signing requirement pin Apple anchor + app ID + helper Team; helper thiếu/chữ ký sai fail-closed, không fallback unsigned.
- Handshake sai protocol không bật controls; capability force discharge fail-closed với helper cũ.
- Sleep hủy polling/request, disable control và invalidate generation. Wake re-probe helper rồi reconnect.
- Mất XPC chuyển khỏi Connected ngay; command UI dùng optimistic state, rollback/readback và sequence guard.

## Safety invariants

- Fan non-System và force discharge không được sống quá heartbeat lease.
- Sleep, wake và heartbeat timeout trả fan về System, tắt force discharge.
- Maintain Charge chạy trong helper; persistence không khôi phục forced fan hoặc force discharge sau boot.
- Thermal guard độc lập với UI: nguồn thời gian monotonic, >=100°C giữ8giây rồi >=105°C trả System theo ngưỡng hiện có. Ba mẫu lỗi và >=6giây thiếu nhiệt độ đáng tin cũng trả System/dừng xả; đây là freshness budget kỹ thuật, không ngưỡng nhiệt mới.
- Discharge chỉ khi maintain+AC+pin>upper, target snapshot=upper, hard deadline60phút trong helper; target/deadline/unplug/invalidIO/sleep/Quit đều stop, verify register Off trước resume charge. Register readback không chứng minh powerflow vật lý.
- Invalid battery IO trong maintain khôi phục default một lần; lỗi restore giữ pending/retry. SensorReads không biến missing capacity thành0 hợp lệ.
- Quit cleanup transient không xóa saved charge intent; Reset/uninstall mới bỏ policy. Helper SIGTERM trả phần cứng an toàn nhưng không ghi đè charge intent; transient fan/watchdog không persist charge mặc định sau restore boot lỗi.
- Không đổi SMC key, byte, retry hoặc sleep trong các block `DO NOT MODIFY` của `Helper/FanController.swift` và `Helper/BatteryController.swift` nếu chưa có hardware matrix.
- Restore/uninstall phải đưa fan về System, cho sạc và tắt force discharge. Restore thử các bước độc lập và báo lỗi một phần; không trả thành công vô điều kiện.
- Battery readback thất bại không được xác nhận optimistic state; UI báo chưa xác nhận. Policy logical không phải bằng chứng dòng điện vật lý đã bằng 0.
- App-hosted XCTest không tự đăng ký daemon hoặc kết nối helper ở `start()`; helper tests dùng fake SMC và persistence closure, không ghi state production.

## Hardware families

- Fan mode: `F{n}Md`, fallback `F{n}md`; `Ftst` optional.
- Tahoe battery: `CHTE` / `CHIE`.
- Legacy battery: `CH0B` / `CH0C`; force discharge `CH0I`.
- Charging truth: `B0AC`; voltage: `B0AV`.
- CHIE-only không có charge-inhibit capability; helper chặn lệnh charge, không rơi vào fallback gây xả. Unsupported control bị khóa kèm lý do; Stop xả vẫn truy cập khi kết quả chưa xác nhận.

## Build graph

`project.yml` là source of truth. XcodeGen tạo project, không track `ThermalControl.xcodeproj`.

- `ThermalControl`: `App/` + `Shared/`.
- `ThermalControlHelper`: `Helper/` + `Shared/`.
- `ThermalControlTests`: app-hosted tests, trừ các test controller/XPC helper.
- `ThermalControlHelperTests`: hostless target test `BatteryController`, `FanController`, `HelperXPCService` và shared dependencies.

Build app embed helper, LaunchDaemon plist, rounded ICNS và `install_helper.sh`. `dist/` chứa release package được track có chủ ý.

## Verification không ghi hardware

```bash
xcodegen generate
xcodebuild test -project ThermalControl.xcodeproj -scheme ThermalControl \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild -project ThermalControl.xcodeproj -scheme ThermalControl \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild -project ThermalControl.xcodeproj -scheme ThermalControl \
  -configuration Release -destination 'platform=macOS,arch=arm64' build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild -project ThermalControl.xcodeproj -scheme ThermalControl \
  -destination 'platform=macOS,arch=arm64' analyze \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Các lệnh trên không cài helper và không ghi SMC. Hardware smoke test, `sudo`, helper install và `--selftest` là bước riêng cần xác nhận rõ.
