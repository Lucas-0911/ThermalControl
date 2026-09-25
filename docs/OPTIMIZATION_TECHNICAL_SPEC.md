# Đặc tả giải pháp kỹ thuật — Tối ưu ThermalControl

**Tác giả:** Hoàng — Tech Lead  
**Ngày:** 25/09/2026  
**Nguồn yêu cầu:** `docs/OPTIMIZATION_REQUIREMENTS.md`  
**Trạng thái:** **Đề xuất để anh Phúc phê duyệt; chưa cho phép triển khai**

---

## 1. Kết luận kiến trúc

Giữ mô hình hai tiến trình hiện có:

- **Thermal Control app:** hiển thị, nhận intent người dùng, đọc local telemetry chỉ để fallback hiển thị; không ghi SMC.
- **Privileged helper:** writer duy nhất của SMC, sở hữu policy pin/quạt, watchdog nhiệt, heartbeat lease và persistence.

Thay đổi tối thiểu nhưng đủ an toàn gồm 5 khối:

1. Một **adaptive polling coordinator** ở app, suy ra một mode duy nhất từ visibility và sleep state.
2. Một API XPC **`getHealthSnapshot`** gộp capability + fan + battery + thermal trong một round-trip.
3. Một **XPC connection state machine** có generation, single-flight và backoff; completion cũ không được mutate state.
4. Một **command transaction** cho từng nhóm control: draft → pending → ack → verified hoặc rollback.
5. Một **client lease fail-safe** trong helper: fan manual/Quiet/Max và force discharge chỉ sống khi app còn heartbeat; Maintain Charge được phép chạy độc lập.

Không thay timing FTST/fan và CHTE/CH0B/CH0C đã reverse-engineer. Không thêm dependency.

### 1.1 Hiện trạng code đã xác minh

- `ThermalViewModel` đã có timer riêng, visibility flags, single-flight `refreshTask` và observer `NSWorkspace.willSleepNotification`/`didWakeNotification` trong working tree.
- `SafetyWatchdog` chạy 2 giây, heartbeat hiện là 5 giây, timeout hiện là 15 giây; thermal trip đã trả fan System và tắt force discharge.
- `XPCClient` có gate timeout 5 giây đảm bảo continuation resume một lần, nhưng interruption/invalidation mới chỉ log.
- Mỗi refresh vẫn fan-out 4 XPC request và app vẫn đọc power/temperature local trùng với helper.
- Chưa có reconnect backoff, connection generation, freshness model, unified snapshot, command verification hoặc trạng thái pending theo control.
- Helper hiện coi hầu hết request là heartbeat, persist cả fan/force-discharge và có thể restore chúng khi daemon khởi động; đây là điểm phải sửa để lease fail-safe có ý nghĩa.
- `PowerObserver` helper hiện chỉ callback wake; chưa chặn watchdog re-apply trong sleep.

---

## 2. Adaptive Polling Engine

### 2.1 Mode duy nhất

`PollingMode = sleeping | hidden | menuVisible | dashboardVisible`; ưu tiên từ cao xuống thấp: `sleeping`, `dashboardVisible`, `menuVisible`, `hidden`. Nếu menu và dashboard cùng mở vẫn chỉ có một coordinator.

| Mode | Health snapshot | Power history | Heartbeat | Hành vi khi vào mode |
|---|---:|---:|---:|---|
| `sleeping` | dừng | dừng | dừng | cancel timer/request, invalidate generation |
| `hidden` | 15 giây | dừng | 5 giây | không đọc SMC local định kỳ |
| `menuVisible` | 2,5 giây | dừng | 5 giây | snapshot ngay |
| `dashboardVisible` | 2 giây | 1 Hz khi chart hiện | 5 giây | snapshot + power sample ngay |

Heartbeat là call nhẹ, tách khỏi telemetry để helper phát hiện app mất trong ≤8 giây mà không buộc đọc SMC. Timeout helper 15 giây cho phép bỏ lỡ hai heartbeat 5 giây mà chưa fallback nhầm. CPU `<0,5%` là gate đo nghiệm thu, không suy luận chỉ từ interval.

### 2.2 Single-flight và coalescing

- Coordinator chỉ giữ một `refreshTask`.
- Tick đến khi request đang chạy chỉ đặt `refreshRequested = true`; sau completion chạy thêm tối đa một refresh nếu mode còn yêu cầu. Không xếp hàng từng tick.
- Visibility/wake/manual Reload có priority cao và được coalesce vào cùng request.
- Power sampler chỉ tồn tại khi **vùng chart thực sự visible**; dashboard bị occluded/minimized hoặc chart chưa xuất hiện thì dừng. Mở lại bắt đầu segment mới, không nội suy gap.
- Dùng timer có tolerance hợp lý ở hidden mode để macOS coalesce wakeup; không đặt tolerance cho power chart 1 Hz.

### 2.3 Unified health snapshot

Bump `protocolVersion` và thêm `getHealthSnapshot(reply:)`. Model `HealthSnapshot: NSSecureCoding` gồm:

- `helperBootID`, `sequence`, `generatedAt`;
- `Capabilities`, `FanStatus`, `BatteryStatus`, `[TempReading]`;
- `safetyState/reason` (`normal`, `heartbeatFallback`, `thermalTrip`, `thermalUnavailable`, `wakeProbeFailed`);
- validity/error theo từng nhóm để lỗi một sensor không làm mất toàn snapshot.

Helper tạo snapshot dưới một serialized read transaction, tái sử dụng kết quả IOKit/SMC trong tick đó; không gọi `status()` lặp gây đọc B0AC/IOPS nhiều lần. Capability chỉ re-probe ở boot/wake hoặc explicit validation, không probe mỗi poll. API cũ giữ tạm một protocol version để rollback package, sau đó xóa khi compatibility window kết thúc.

### 2.4 Freshness

App lưu `lastUpdatedAt` riêng cho fan, battery, thermal, power và `lastValidSnapshot`.

- Stale khi `now - lastUpdatedAt > 2 × expectedInterval` (hidden: 30s; menu: 5s; dashboard telemetry: 4s; power: 2s).
- Sau sleep, tất cả group stale ngay; snapshot trước sleep chỉ được hiển thị mờ/“—”, không enable control.
- Sensor không hợp lệ bị loại (NaN/∞, nhiệt ngoài miền sanity, RPM/min/max không hợp lệ). Không biến lỗi thành `0`.
- Connection chỉ là `connected` sau capability/protocol validation và một health snapshot hợp lệ cùng `helperBootID`.

---

## 3. Sleep/Wake lifecycle

### 3.1 App

**willSleep**

1. Chuyển state `sleeping`, disable control ngay.
2. Invalidate timer và cancel refresh/reconnect/power burst/debounce task.
3. Tăng `connectionGeneration`; completion thuộc generation cũ bị bỏ.
4. Pending command chuyển thành `unverified`, rollback UI về confirmed snapshot; giữ draft an toàn.
5. Không gửi command mới. Không dùng timeout sau wake để hiện modal lỗi cũ.

**didWake**

1. Giữ control disabled, state `reconnecting`.
2. Delay ban đầu 1 giây (không coi đây là hardware guarantee).
3. Invalidate connection cũ; tạo generation mới.
4. Connect → ping/protocol validation → capability re-probe → health snapshot.
5. Nếu thành công, cập nhật confirmed state rồi mới `connected`; mục tiêu ≤5 giây.
6. Nếu helper/SMC chưa sẵn sàng, vào backoff; manual Retry bỏ qua thời gian chờ nhưng vẫn single-flight.

### 3.2 Helper

Mở rộng `PowerObserver` với `onSleep` và `onWake`:

- **onSleep:** actor watchdog đặt `sleeping = true`, dừng battery tick/fan re-apply/thermal read; tắt force discharge best-effort trước sleep; không diễn giải app heartbeat vắng trong sleep như crash.
- **onWake:** reset thermal counters; force discharge vẫn off; `fan.probe()` và `battery.probe()` trước mọi restore. Fan giữ/về System làm baseline. Chỉ re-apply Maintain sau khi đọc được battery %, AC và key family; lỗi probe/write → degraded.
- Không tự re-apply Quiet/Custom sau thermal fallback hoặc wake verify fail. User phải chọn lại.

---

## 4. XPC resilience và reconnect state machine

### 4.1 State

`disconnected | connecting | validating | connected | reconnecting(attempt) | needsApproval | sleeping | restoring | degraded(error)`.

Event được serialize trên `@MainActor` coordinator hoặc một actor riêng; không để timer, callback và button cùng sửa connection độc lập.

### 4.2 Generation và stale completion

- Mỗi connection có `generation: UInt64`; mỗi request capture generation.
- Interruption, invalidation, sleep, manual retry hoặc replacement đều tăng generation.
- Reply/timeout chỉ được apply nếu generation còn khớp và request ID vẫn là latest cho operation group.
- Invalidate connection cũ trước khi resume connection mới; chỉ một connect attempt tồn tại.
- Error handler phải hoàn tất request gate ngay với typed transport error, không chờ đủ 5 giây.

### 4.3 Detection và backoff

- `interruptionHandler`/`invalidationHandler`: trong callback chuyển khỏi connected, stale telemetry, disable control, schedule reconnect.
- Ping mỗi 5 giây với hard timeout 2 giây: đáp ứng phát hiện silent hang ≤7–8 giây.
- Backoff: `1, 2, 4, 8, 10` giây, cap 10 giây, jitter ±20%; reset sau một validation thành công.
- `needsApproval` không auto-spin; chỉ retry khi permission state đổi hoặc người dùng bấm Retry.
- Manual Retry cancel delay hiện tại và thử ngay, nhưng không song song với attempt đang chạy.

### 4.4 Timeout

- Transport hard timeout: ping 2s; snapshot/command 5s.
- Mục tiêu fan ack ≤1,5s và pin ack ≤2s là SLO đo thực tế, không dùng timeout ngắn để kết luận hardware chưa áp dụng vì FTST/charge settle có timing tải trọng.
- Timeout nghĩa là **unknown outcome**, không phải chắc chắn thất bại; UI rollback và bắt buộc snapshot xác minh trước thao tác tiếp theo.

---

## 5. Command transaction và UX

Mỗi nhóm `fan`, `chargePolicy`, `forceDischarge`, `restore` có state độc lập:

`idle(confirmed) → pending(requestID, draft) → acked → verifying → confirmed | failed | unverified`.

- Pending hiển thị ≤100ms và chỉ disable control cùng nhóm.
- Debounce hiện tại (fan 80ms, charge 120ms) được giữ; intent mới tăng sequence, reply cũ bị bỏ.
- Protocol command nhận `requestID`; helper trả `CommandAck(requestID, accepted, errorCode, completedAt)`. Ack chỉ xác nhận helper hoàn thành write sequence, chưa thay thế verify.
- Sau ack, app yêu cầu/coalesce health snapshot. Chỉ báo thành công khi mode/target hoặc charge policy khớp snapshot.
- Nếu fail/timeout/mismatch: rollback về `lastConfirmed`, giữ Custom RPM/charge draft nếu hợp lệ, stale control và đưa Retry/Restore; modal chỉ một lần cho cùng request.
- `restoreSystemControl` trả kết quả từng phần (`fan`, `charge`, `forceDischarge`) và verify; không trả success toàn cục nếu một phần lỗi.

Helper tiếp tục clamp/validate độc lập. Fan index phải tồn tại; RPM clamp theo min/max vừa probe. Charge pair dùng một `ChargeLimits` contract ở app/helper.

---

## 6. Hardware fail-safe và persistence

### 6.1 Client lease

- Khi app kết nối, tạo `sessionID`; heartbeat/command hợp lệ gia hạn lease.
- **Fan non-System** và **force discharge** là session-scoped, không tự khôi phục sau app/helper crash.
- Khi lease quá 15 giây: trong tick watchdog gần nhất, restore fan System + release FTST; tắt force discharge và verify best-effort; log trigger/action/result. Với tick 2 giây, hoàn tất force-discharge off ≤2 giây sau khi timeout được kết luận, đạt yêu cầu ≤5 giây.
- Maintain Charge là durable policy và tiếp tục hysteresis 2 giây độc lập; khi `percent <= lower`, bắt buộc enable charging.

### 6.2 Persistence migration

`PersistedState` schema mới:

- Persist: Maintain enabled, upper/lower, và dữ liệu cần tương thích.
- Không persist `forceDischarge = true` như policy có thể auto-restore.
- Không auto-restore Quiet/Max/Custom ở helper boot khi chưa có live app lease; fan boot baseline luôn System.
- Migration đọc schema cũ nhưng cưỡng bức fan System và force discharge false; không làm mất Maintain setting.

### 6.3 Quit bình thường

Thêm explicit `prepareForClientExit`: restore fan System, force discharge off, giữ Maintain, persist rồi ack. App dùng termination handshake có timeout ngắn; nếu app chết trước ack, lease watchdog vẫn là hàng rào cuối. Không block quit vô hạn.

### 6.4 Thermal và mất telemetry

- Giữ threshold/timing hiện có (`thermalCeiling`, cap/hotspot cap, hold 8s) cho đến khi test máy thật cho phép thay đổi.
- Một tick không đọc được nhiệt: giữ policy, log debug.
- Đề xuất **3 tick liên tiếp / 6 giây** không có bất kỳ thermal trip sensor hợp lệ trong lúc fan non-System: degraded, fan System, force discharge off. Reset counter khi có reading hợp lệ.
- Thermal trip là latched safety reason; không auto-restore fan policy khi nhiệt giảm.
- Không chủ động inhibit charging khi thermal trip. Giữ Maintain hiện tại nhưng tắt force discharge; macOS/SMC vẫn quản lý thermal charging. Việc tự ghi charge gate dựa trên CPU sensor chưa chứng minh có thể làm tăng cycle/xả pin và xung đột quản lý pin của Apple.

### 6.5 Hardware write verification

Không sửa chuỗi FTST và CHTE/CH0B/CH0C. Verification thực hiện sau chuỗi hiện hữu bằng status/readback có khả năng quan sát; nếu key không cho readback đáng tin, trả `accepted-but-unverified`, không giả success.

---

## 7. Logging và quan sát

Dùng `os.Logger` category hiện có; bổ sung event chuẩn:

- lifecycle: sleep, wake, probe start/result;
- XPC: connect generation, interrupt/invalidate, retry attempt/delay, validation result;
- command: type, requestID rút gọn, latency, ack/verify/error code;
- safety: heartbeat age, thermal value/missing count, fallback action và verify result.

Không log token/session đầy đủ, credential hoặc raw private payload. Dùng signpost/counter trong Debug/benchmark build để đếm XPC request, SMC read, wakeup và command latency.

---

## 8. Đánh giá 6 quyết định cần PO phê duyệt

| # | Khuyến nghị Tech Lead | Cơ sở kỹ thuật / điều kiện |
|---|---|---|
| 1 | **Duyệt:** Quit → fan System, force discharge off, giữ Maintain. | Không còn UI giám sát thì không giữ forced fan; Maintain là policy bền vững và helper có hysteresis độc lập. Cần termination handshake + watchdog fallback. |
| 2 | **Duyệt:** Crash/mất heartbeat → fan System, force discharge off, giữ Maintain. | Đây là lease model an toàn nhất. Đồng thời phải cấm restore fan/force-discharge từ persisted state khi helper restart. |
| 3 | **Duyệt:** Thermal trip → fan System + force discharge off; **không thêm inhibit charging**. | CPU/GPU sensor không đủ để suy ra nhiệt cell; ghi charge key có thể xung đột SMC. Giữ Maintain hiện tại, để Apple SMC quản lý thermal charge; chỉ đổi khi có battery-temperature sensor và test matrix thật. |
| 4 | **Duyệt có gate máy thật:** timeout 15s, heartbeat 5s, watchdog tick 2s. | Không đụng timing FTST. Test sleep/wake, app SIGKILL, main-thread stall và ít nhất các family SMC đang hỗ trợ; không fallback giả qua 20 sleep/wake. |
| 5 | **Duyệt:** upper `[40,99]`, lower `[20, upper-5]`. | Loại edge 20/18, giảm chattering và không khuyến khích vận hành pin ở SOC quá thấp. Migration clamp dữ liệu cũ một lần và UI giải thích thay đổi. |
| 6 | **Duyệt như tiêu chí trên máy chuẩn:** app CPU avg `<0,5%` hidden/10 phút; wakeups so với baseline. | Không thể cam kết tuyệt đối mọi máy/macOS. Pass khi Release/no debugger, cùng workload; đồng thời không tăng helper latency hoặc bỏ safety event. |

---

## 9. Traceability Matrix BR/FR → giải pháp → file/module

| Requirement | Giải pháp | File/module tác động chính |
|---|---|---|
| BR-01; FR-P01/P03/P06; FR-M02 | PollingMode, chart-gated 1Hz, single-flight/coalescing | `App/ViewModels/ThermalViewModel.swift`, `PowerViewModel.swift`, `DashboardView.swift`, `MenuBarView.swift` |
| BR-02; FR-P02/P03/P07; FR-M01 | immediate snapshot, per-group freshness/validity | `ThermalViewModel.swift`, `FanViewModel.swift`, `BatteryViewModel.swift`, UI components, localization |
| BR-03; FR-P04/P05; FR-F05; FR-B05 | app sleep observer; helper onSleep/onWake; re-probe then validate | `ThermalViewModel.swift`, `Helper/PowerObserver.swift`, `SafetyWatchdog.swift`, controllers |
| BR-04; FR-X01–X04 | connection state machine, generation, ping timeout, backoff/manual retry | `App/Services/XPCClient.swift`, `HelperConnectionState.swift`, `ThermalViewModel.swift`, `HelperStatusRow.swift` |
| BR-05; FR-X05–X08 | per-control transaction, requestID, ack + snapshot verify, rollback | `FanViewModel.swift`, `BatteryViewModel.swift`, `ThermalViewModel.swift`, `ThermalHelperProtocol.swift`, XPC service/models |
| BR-06; FR-F01–F06 | helper clamp, client lease 15s, thermal/missing-telemetry fallback, idempotent restore | `FanController.swift`, `SafetyWatchdog.swift`, `Constants.swift`, helper tests |
| BR-07; FR-B01–B08 | ChargeLimits validation, FD session pin, durable Maintain, AC-safe tick, idempotent Full | `ChargeLimits.swift`, `BatteryController.swift`, `SafetyWatchdog.swift`, `PersistedState.swift`, `StateStore.swift` |
| BR-08; FR-M03/M04 | structured Logger events + latency/safety reason | `Shared/Support/Log.swift`, XPC client/service, watchdog/controllers |
| BR-09 | capability-driven controls, protocol version, persisted migration | `Capabilities.swift`, `HealthSnapshot` model, `ThermalHelperProtocol.swift`, `PersistedState.swift`, views |

### Ánh xạ đầy đủ từng FR

| FR | Solution / file trọng tâm |
|---|---|
| FR-P01 | hidden mode: snapshot 15s, power 0Hz — `ThermalViewModel`, `PowerViewModel` |
| FR-P02 | menu open snapshot ngay, 2,5s — `MenuBarView`, polling coordinator |
| FR-P03 | dashboard telemetry 2s, chart-visible power 1Hz, một coordinator — `DashboardView`, polling coordinator |
| FR-P04 | app/helper sleep suspension — `ThermalViewModel`, `PowerObserver`, `SafetyWatchdog` |
| FR-P05 | wake generation mới, probe + validate + snapshot — XPC coordinator/controllers |
| FR-P06 | `refreshTask` + dirty flag và unified snapshot — coordinator/XPC protocol/service |
| FR-P07 | timestamp/validity từng group — snapshot models và view models |
| FR-X01 | interruption/invalidation event vào state machine — `XPCClient`, `ThermalViewModel` |
| FR-X02 | bounded backoff + manual Retry — connection coordinator/`HelperStatusRow` |
| FR-X03 | connect single-flight, invalidate-before-replace — `XPCClient` |
| FR-X04 | capability/protocol + snapshot validation trước Connected — coordinator/service |
| FR-X05 | requestID + sequence/generation gate — command models/view models/service |
| FR-X06 | pending riêng từng control — `FanViewModel`, `BatteryViewModel`, views |
| FR-X07 | ack rồi snapshot verify — command coordinator/unified snapshot |
| FR-X08 | rollback `lastConfirmed`, giữ draft, dedupe error — view models/alert presenter |
| FR-F01 | helper validate index và clamp min/max — `FanController` |
| FR-F02 | client lease timeout 15s → System — `SafetyWatchdog`, `Constants` |
| FR-F03 | latched thermal fallback, không auto re-apply — watchdog/snapshot safety reason |
| FR-F04 | one-read tolerance; 3 missing ticks → degraded/System — watchdog |
| FR-F05 | wake probe trước policy, verify fail giữ System — watchdog/controllers |
| FR-F06 | idempotent System/Ftst release + partial verify — `FanController`/restore result |
| FR-B01 | shared `[40,99]`, `[20, upper-5]` validation — `ChargeLimits`, app/helper |
| FR-B02 | Maintain chạy ở helper tick 2s — `BatteryController`, watchdog |
| FR-B03 | FD session-scoped, off ở tick sau lease timeout — watchdog/controller |
| FR-B04 | durable Maintain; ≤lower luôn enable charge — controller/persistence |
| FR-B05 | wake/restart probe key family + percent/AC trước apply — controller/watchdog |
| FR-B06 | thermal trip tắt FD, giữ Maintain — watchdog |
| FR-B07 | idempotent Full/Restore + verify từng phần — controller/XPC result |
| FR-B08 | AC-aware state, tránh write lặp không đổi — `BatteryController.tick`, snapshot |
| FR-M01 | validity filter, giữ last valid/“—”, không zero giả — snapshot/view models |
| FR-M02 | chart visibility gate và gap/new segment — dashboard/power model |
| FR-M03 | structured categories + latency/result, không secret — `Log.swift`, XPC/commands |
| FR-M04 | safety trigger/context/action/verify result — watchdog/controllers |

---

## 10. Kế hoạch test và gate bàn giao

### Automated

1. Poll scheduler: mode transitions, menu+dashboard coalescing, không overlap, no 1Hz hidden.
2. XPC state machine: interruption/invalidation/timeout, one reconnect, backoff reset, manual retry, stale generation ignored.
3. Command sequencing: old reply ignored, timeout rollback, ack-but-mismatch → unverified.
4. Freshness: threshold theo mode, sleep invalidation, invalid sensor không thành 0.
5. Watchdog fake clock/SMC: 15s lease, FD off, Maintain còn chạy, thermal trip, 3 missing thermal ticks.
6. Persistence migration: schema cũ không restore forced fan/FD, giữ Maintain; charge bounds 40/20/gap 5.
7. Unified snapshot secure-coding/protocol compatibility và partial validity.

### Hardware/manual

- 20 sleep/wake; 10 helper kill/restart; app SIGKILL khi từng fan mode và FD on.
- Verify FTST release/System, FD off, Maintain lower threshold cho sạc lại.
- Family Tahoe (`CHTE/CHIE`) và legacy (`CH0B/CH0C`) trên máy thật; fanless/desktop không hiện control sai.
- Không đổi byte/sleep/retry trong hardware sequence nếu test chưa phê duyệt.

### Benchmark/Release

Ba bài 10 phút: hidden, menu open, dashboard/chart. Báo cáo CPU avg/p95, wakeups, XPC/min, SMC reads/min, memory, Energy Impact và helper tick latency. Nam chỉ đóng gói sau QC pass; warning/runtime safety log là gate.

---

## 11. Thứ tự triển khai sau phê duyệt

1. Chốt 6 quyết định PO và freeze hardware timing.
2. Protocol/model (`HealthSnapshot`, ack, version) + helper snapshot transaction.
3. XPC state machine/generation/backoff.
4. Polling/freshness/visibility và command transaction UI.
5. Helper lease, sleep/wake, persistence migration, thermal-unavailable fallback.
6. Automated tests → QC hardware matrix → Release benchmark/package.

**Điều kiện bắt đầu code:** anh Phúc phê duyệt mục 8, đặc biệt hành vi Quit/crash/thermal, timeout 15 giây và miền charge limit.