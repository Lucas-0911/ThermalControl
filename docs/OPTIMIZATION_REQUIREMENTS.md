# Đặc tả nghiệp vụ — Tối ưu ThermalControl

**Vai trò soạn:** Linh — Business Analyst  
**Ngày:** 25/09/2026  
**Trạng thái:** Draft để Hoàng (Tech Lead) phân tích giải pháp và anh Phúc phê duyệt; **chưa triển khai**.

## 1. Mục tiêu đợt tối ưu

1. Giảm tài nguyên và điện năng khi ThermalControl chỉ chạy nền trên menu bar, nhưng không làm suy giảm chức năng bảo vệ phần cứng.
2. App tự phục hồi rõ ràng sau Sleep/Wake, helper restart/crash hoặc XPC gián đoạn; không để UI hiển thị trạng thái điều khiển sai.
3. Lệnh quạt và giới hạn sạc cho phản hồi tức thời, có trạng thái đang xử lý, kết quả xác nhận và lỗi có thể khắc phục.
4. Mọi lỗi app/helper phải đưa phần cứng về trạng thái an toàn đã thống nhất, không để quạt bị khóa thấp hoặc force-discharge kéo dài ngoài ý muốn.

## 2. Phạm vi và hiện trạng đã rà soát

### 2.1 Fan Control

**Hiện có**

- Chế độ System, Quiet, Max, Custom theo từng quạt; RPM được clamp theo min/max SMC.
- UI cập nhật optimistic, chống ghi đè khi người dùng đang kéo/chỉnh; Custom RPM được lưu.
- Helper re-apply policy quạt khoảng 10 giây/lần.
- Nếu mất heartbeat quá 45 giây, helper trả quạt về System.
- Nếu nhiệt cao liên tục theo ngưỡng hiện tại, watchdog trả quạt về System.

**Khoảng trống/rủi ro**

- App polling trạng thái quạt chung chu kỳ 3 giây kể cả khi UI không được xem.
- XPC interruption/invalidation hiện chỉ ghi log, chưa tự reconnect theo trạng thái có kiểm soát.
- Không có trạng thái “đang áp dụng/đã xác nhận” riêng cho từng lệnh; timeout 5 giây có thể làm trải nghiệm chậm và khó hiểu.
- Quit bình thường chưa chủ động gửi restore; hiện fail-safe phụ thuộc heartbeat 45 giây. Cần thống nhất rằng đóng app có giữ chế độ quạt hay trả System ngay.

### 2.2 Battery Charge Limiting

**Hiện có**

- Full hoặc Custom với upper/lower; ngắt/cho sạc; force discharge.
- Helper kiểm tra pin mỗi 2 giây và giữ hysteresis upper/lower.
- Policy được persist và restore khi helper khởi động lại.
- Restore System đưa pin về cho sạc, bỏ maintain và force discharge.

**Khoảng trống/rủi ro**

- Policy pin tiếp tục tồn tại khi app mất heartbeat; force discharge cũng có thể tiếp tục dù app đã crash.
- Chưa có quy tắc nghiệp vụ riêng cho app crash, helper crash, mất nguồn AC, Sleep/Wake và nhiệt quá cao.
- UI có thể optimistic nhưng không rollback đầy đủ về snapshot xác nhận cuối khi lệnh pin thất bại.
- Biên `upper = 20` hiện có thể tạo `lower = 18`; cần chốt lại miền hợp lệ mong muốn trước khi sửa.

### 2.3 Power/Temperature Monitoring

**Hiện có**

- UI refresh tổng hợp mỗi 3 giây.
- Power history lấy mẫu mỗi 1 giây liên tục, cửa sổ biểu đồ 30 giây.
- Mỗi refresh có 4 XPC round-trip độc lập (capability, fan, battery, thermal), đồng thời app đọc local battery/power và đọc lại nhiệt local.
- Helper watchdog đọc nhiệt an toàn độc lập với UI.

**Khoảng trống/rủi ro**

- Lấy mẫu power 1 giây vẫn chạy khi dashboard/menu đóng; không mang thêm giá trị vì biểu đồ chỉ giữ 30 giây.
- Một lần refresh có thể đọc nhiệt ở cả app và helper, gây I/O SMC trùng lặp.
- Timer không có lifecycle theo UI visible/hidden hoặc Sleep/Wake.
- Chưa có dấu “cập nhật lúc…”/stale để phân biệt số liệu mới với snapshot cũ.

### 2.4 Helper XPC Service

**Hiện có**

- Privileged mach service, kiểm tra Team ID, timeout async 5 giây.
- Watchdog độc lập 2 giây; PowerObserver của helper re-probe/re-apply sau wake.
- Persist policy atomically; helper restart khôi phục fan và pin.

**Khoảng trống/rủi ro**

- App chưa xử lý lifecycle Sleep/Wake; helper có xử lý wake nhưng app có thể giữ connection/snapshot cũ.
- Interruption/invalidation chưa phát tín hiệu state cho ViewModel, chưa backoff reconnect.
- Chưa có health snapshot duy nhất để giảm số round-trip/poll và xác định freshness.
- Nếu helper không phản hồi, từng request chờ tối đa 5 giây; nhiều request đồng thời có thể tạo tải và trạng thái kết quả không đồng nhất.

## 3. Nguyên tắc nghiệp vụ bắt buộc

- **Safety ưu tiên hơn setting:** Khi không chắc lệnh đã được áp dụng, UI không được tuyên bố thành công.
- **Watchdog độc lập:** Việc giảm polling app không được giảm chu kỳ bảo vệ nhiệt/quạt hoặc charge hysteresis trong helper.
- **Single writer:** Chỉ helper được ghi SMC; app chỉ đọc local khi helper mất kết nối và chỉ để hiển thị.
- **Không stale control:** Khi mất helper, disable toàn bộ control; dữ liệu cũ phải có nhãn stale, không giả như đang cập nhật.
- **Khôi phục có giới hạn:** Tự reconnect không được tạo vòng lặp dày; phải backoff và vẫn có nút thử lại ngay.
- **Không đổi hardware timing đã kiểm chứng** trong chuỗi FTST/fan và CHTE/CH0B/CH0C nếu chưa có test trên máy thật.

## 4. Business Requirements (BR)

| ID | Yêu cầu | Ưu tiên | Chỉ số thành công |
|---|---|---:|---|
| BR-01 | Chạy nền tiết kiệm điện | Must | Khi không mở menu/dashboard: app không lấy mẫu power 1 Hz; app process trung bình CPU <0,5% trong bài đo idle 10 phút trên máy chuẩn; không regression watchdog helper |
| BR-02 | Dữ liệu đủ mới khi người dùng xem | Must | Mở menu có snapshot đầu tiên ≤2 giây; dữ liệu visible được làm mới phù hợp mà không giật UI |
| BR-03 | Tự phục hồi Sleep/Wake | Must | Sau wake, trạng thái helper và policy được xác minh ≤5 giây; control chỉ mở khi snapshot hợp lệ |
| BR-04 | Tự phục hồi XPC/helper | Must | Phát hiện mất kết nối ≤8 giây; tự reconnect sau khi helper sẵn sàng, không cần relaunch app |
| BR-05 | Phản hồi lệnh minh bạch | Must | UI pending ≤100 ms; fan xác nhận thông thường ≤1,5 giây, pin ≤2 giây; timeout/lỗi rollback và chỉ dẫn retry |
| BR-06 | Fail-safe quạt | Must | App/helper lỗi không để quạt khóa Quiet/Custom thấp; quá nhiệt luôn chuyển quyền điều khiển về System |
| BR-07 | Fail-safe pin | Must | Force discharge không được tiếp tục khi mất app heartbeat; policy maintain không tạo trạng thái pin bị xả sâu hoặc không thể sạc lại |
| BR-08 | Quan sát và chẩn đoán | Should | Log có event sleep/wake, connect/disconnect/retry, command latency/result và lý do safety fallback; không chứa dữ liệu nhạy cảm |
| BR-09 | Tương thích | Must | Không mất setting đang dùng, không phá các dòng máy/family SMC đang hỗ trợ; fanless/desktop tiếp tục ẩn control không áp dụng |

## 5. Functional Requirements (FR)

### 5.1 Polling thích ứng

- **FR-P01 — UI hidden/background:**
  - Dừng power history sampling.
  - Fan/nhiệt không cần app poll nhanh; snapshot nền tối đa 10–15 giây/lần hoặc theo event/heartbeat do Tech Lead chọn.
  - Battery display tối đa 15 giây/lần; charge hysteresis 2 giây trong helper giữ nguyên.
- **FR-P02 — Menu bar panel visible:** Lấy snapshot ngay, sau đó làm mới telemetry khoảng 2–3 giây/lần.
- **FR-P03 — Dashboard visible:** Power chart 1 giây/lần; fan/nhiệt/pin 2–3 giây/lần; không tạo hai luồng polling trùng nếu menu và dashboard cùng mở.
- **FR-P04 — Sleep:** Dừng timer/command mới ở app; helper ghi nhận sleep và không thực hiện re-apply không cần thiết trong thời gian ngủ.
- **FR-P05 — Wake:** Reconnect/validate connection, re-probe capability, lấy snapshot mới; không dùng snapshot trước sleep để enable control.
- **FR-P06 — Coalescing:** Một tick chỉ tạo tối đa một refresh đang chạy; tick mới không chồng lên request cũ. Ưu tiên một health snapshot tổng hợp hoặc cơ chế tương đương để tránh đọc SMC trùng.
- **FR-P07 — Freshness:** Mỗi nhóm telemetry có thời điểm cập nhật cuối. Nếu quá 2 chu kỳ dự kiến mà chưa có dữ liệu mới, UI đánh dấu stale.

### 5.2 XPC lifecycle và command UX

- **FR-X01:** Interruption/invalidation phải chuyển state sang reconnecting/disconnected ngay và disable control.
- **FR-X02:** App tự reconnect với backoff có giới hạn; khi người dùng bấm Retry thì thử ngay, không chờ backoff.
- **FR-X03:** Chỉ một reconnect attempt tại một thời điểm; kết nối cũ phải invalidate trước khi thay thế.
- **FR-X04:** Khi helper trở lại, app bắt buộc đọc capability + trạng thái thật trước khi báo Connected.
- **FR-X05:** Mỗi lệnh điều khiển có request identity/sequence; reply cũ không được ghi đè intent mới hơn.
- **FR-X06:** UI hiển thị pending ngay; trong lúc pending disable đúng control liên quan, không khóa toàn app.
- **FR-X07:** Thành công chỉ khi helper ack; sau ack, snapshot kế tiếp phải xác nhận trạng thái phần cứng. Nếu không khớp, báo “không xác minh được” và cho Retry/System Restore.
- **FR-X08:** Timeout hoặc lỗi phải rollback về trạng thái xác nhận gần nhất, giữ draft của người dùng nếu an toàn, và không hiện modal lặp liên tục.

### 5.3 Fan safety

- **FR-F01:** Clamp RPM theo min/max của từng fan; request ngoài miền không được ghi thẳng xuống SMC.
- **FR-F02:** Nếu mất app heartbeat quá ngưỡng fail-safe, helper chuyển toàn bộ fan về System và ghi log lý do. Mục tiêu đề xuất: 15 giây; mức 45 giây hiện tại chỉ giữ nếu test máy thật chứng minh cần thiết.
- **FR-F03:** Nếu nhiệt vượt ngưỡng safety liên tục, helper về System bất kể mode UI; UI sau reconnect phải phản ánh fallback, không tự áp lại Quiet/Custom.
- **FR-F04:** Nếu không đọc được nhiệt một lần, không tự thay đổi mode; nếu mất toàn bộ thermal telemetry liên tiếp trong khoảng do Tech Lead xác định, coi là degraded và ưu tiên System.
- **FR-F05:** Sau wake, helper re-probe fan và chỉ re-apply policy không nguy hiểm sau khi SMC sẵn sàng. Nếu verify thất bại, giữ System.
- **FR-F06:** Restore System là idempotent; có thể gọi nhiều lần và kết quả cuối luôn mode System/Ftst released.

### 5.4 Battery safety

- **FR-B01:** Upper/lower phải được validate tại app và helper; lower luôn nhỏ hơn upper theo khoảng tối thiểu đã phê duyệt.
- **FR-B02:** Maintain charge là policy chạy trong helper, không phụ thuộc polling UI.
- **FR-B03:** Khi mất app heartbeat, helper **tắt force discharge** ở tick gần nhất; không tự bật lại khi app reconnect. Mục tiêu hoàn tất ≤5 giây sau khi helper kết luận heartbeat timeout.
- **FR-B04:** Maintain limit được giữ qua app quit/crash theo khuyến nghị BA; khi pin ≤ lower phải cho sạc lại. Không được để charging-inhibited vô thời hạn dưới lower.
- **FR-B05:** Sau wake/helper restart, helper re-probe key family, đọc %/AC rồi mới re-apply maintain. Nếu key/write verify lỗi, chuyển trạng thái degraded và không báo thành công.
- **FR-B06:** Khi nhiệt safety trip, tắt force discharge; hành vi maintain/charging còn lại theo quyết định PO ở mục 9.
- **FR-B07:** “Full charge/Restore” phải bỏ maintain, bật charging và tắt force discharge; thao tác idempotent.
- **FR-B08:** Mất AC khi force discharge/maintain không được gây vòng write liên tục; UI phản ánh On Battery ở snapshot tiếp theo.

### 5.5 Monitoring và logging

- **FR-M01:** Hottest temperature và RPM hiển thị từ snapshot mới nhất hợp lệ; giá trị không hợp lệ bị loại, không biến thành 0 giả.
- **FR-M02:** Power chart chỉ lưu/lấy mẫu khi dashboard hoặc vùng chart đang visible; sau khi mở lại, bắt đầu cửa sổ mới hoặc thể hiện gap, không nội suy dữ liệu nền không tồn tại.
- **FR-M03:** Log dùng category và mức phù hợp; command log gồm loại lệnh, thời lượng, success/fail nhưng không log credential/token.
- **FR-M04:** Safety event phải lưu: trigger, nhiệt/timeout liên quan, hành động fallback và kết quả verify.

## 6. User Stories và Acceptance Criteria

### US-01 — Chạy nền tiết kiệm pin

**Là** người dùng để ThermalControl chạy cả ngày, **tôi muốn** app giảm hoạt động khi không xem UI, **để** không làm hao pin ngầm.

**AC**

1. Given app connected và menu/dashboard đóng, when theo dõi 60 giây, then không có power sample 1 Hz và không có request refresh chồng nhau.
2. Given UI hidden, then watchdog fan/thermal và charge hysteresis của helper vẫn hoạt động đúng chu kỳ safety.
3. Given bài đo idle 10 phút trên máy chuẩn, then app CPU trung bình <0,5%; báo cáo trước/sau có CPU, wakeups và Energy Impact.
4. Given menu được mở, then snapshot hiển thị trong ≤2 giây và không cần restart app.
5. Given dashboard đóng, then power history không tiếp tục tích mẫu; mở lại chart không vẽ dữ liệu giả cho khoảng đã đóng.

### US-02 — Xem dữ liệu mới, không bị stale lừa

**Là** người dùng, **tôi muốn** biết dữ liệu có còn mới, **để** không ra quyết định dựa trên snapshot cũ.

**AC**

1. Given refresh thành công, then UI cập nhật timestamp/freshness nội bộ và bỏ trạng thái stale.
2. Given quá 2 chu kỳ refresh không có snapshot mới, then telemetry được đánh dấu stale; control bị disable nếu helper health không còn hợp lệ.
3. Given giá trị sensor lỗi/ngoài miền, then UI giữ giá trị hợp lệ cuối có nhãn stale hoặc hiển thị “—”, không hiển thị 0°C/0 RPM như dữ liệu thật.

### US-03 — Sleep/Wake liền mạch

**Là** người dùng gập/mở máy, **tôi muốn** ThermalControl tự hồi phục, **để** không phải relaunch và không áp policy sai.

**AC**

1. Given máy chuẩn bị sleep, then app dừng polling và không gửi command mới; request đang chạy phải kết thúc an toàn hoặc bị hủy về trạng thái chưa xác nhận.
2. Given máy wake, then control ở trạng thái reconnecting cho tới khi capability và snapshot mới hợp lệ.
3. Given helper sẵn sàng, then trong ≤5 giây sau wake UI Connected, RPM/nhiệt/pin mới và policy thực được hiển thị.
4. Given helper chưa sẵn sàng, then UI báo đang kết nối/mất helper, tự retry có backoff và cho phép Retry thủ công.
5. Given re-apply policy sau wake thất bại, then fan giữ/về System; pin không bật force discharge; lỗi chỉ hiện một lần có hướng xử lý.

### US-04 — Helper crash/mất XPC và tự hồi phục

**Là** người dùng, **tôi muốn** app tự xử lý helper mất kết nối, **để** control không treo hoặc báo thành công giả.

**AC**

1. Given connection interruption/invalidation, then trong ≤1 giây từ callback app đổi khỏi Connected và disable control.
2. Given helper không trả lời nhưng callback không đến, then heartbeat/timeout phát hiện mất kết nối trong ≤8 giây.
3. Given helper được launch lại, then app tự reconnect và xác minh snapshot mà không relaunch.
4. Given nhiều timer/event cùng yêu cầu reconnect, then chỉ có một attempt đang chạy.
5. Given reconnect liên tục thất bại, then tần suất retry giảm dần, CPU không tăng bất thường và nút Retry vẫn hoạt động ngay.

### US-05 — Đổi mode/RPM quạt có xác nhận

**Là** người dùng điều chỉnh quạt, **tôi muốn** thấy lệnh đang chạy và kết quả thật, **để** tin rằng phần cứng đã đổi.

**AC**

1. Given user chọn System/Quiet/Max/Custom, then selected control/pending xuất hiện ≤100 ms.
2. Given helper ack thành công, then pending kết thúc thông thường ≤1,5 giây và snapshot sau đó khớp mode/target.
3. Given user kéo RPM liên tục, then các thay đổi được debounce/coalesce; reply cũ không ghi đè giá trị mới.
4. Given RPM ngoài min/max, then cả app và helper clamp/reject theo cùng quy tắc; không ghi giá trị ngoài miền.
5. Given command timeout/fail, then UI rollback mode đã xác nhận, giữ draft Custom để retry và hiện lỗi hành động được.
6. Given nhiệt safety trip, then helper về System; UI không tự áp lại mode cũ sau reconnect.

### US-06 — Đặt giới hạn sạc có phản hồi đúng

**Là** người dùng bảo vệ pin, **tôi muốn** giới hạn sạc được xác nhận nhanh và chính xác, **để** biết máy đang theo policy nào.

**AC**

1. Given user chỉnh upper/lower, then draft hiển thị ngay, command được debounce/coalesce và pending ≤100 ms.
2. Given helper ack, then pending kết thúc ≤2 giây và snapshot xác nhận upper/lower/maintain.
3. Given percent ≥ upper, then charging được inhibit; given percent ≤ lower, then charging được cho phép lại trong tối đa một tick helper + thời gian hardware settle.
4. Given command fail/timeout, then UI rollback về policy xác nhận cuối, không báo Maintain active giả.
5. Given user chọn Full/Restore, then maintain=false, forceDischarge=false, chargingEnabled=true sau xác nhận.
6. Given upper/lower không hợp lệ, then UI chặn hoặc sửa rõ ràng trước khi gửi; helper vẫn validate độc lập.

### US-07 — Fail-safe khi app bị tắt/crash

**Là** người dùng, **tôi muốn** phần cứng trở về trạng thái an toàn khi app biến mất, **để** không bị quạt thấp hoặc xả pin ngoài ý muốn.

**AC**

1. Given fan đang Quiet/Custom và app mất heartbeat, then helper chuyển fan System trong ngưỡng đã phê duyệt và verify best-effort.
2. Given force discharge đang bật và app mất heartbeat, then helper tắt force discharge; policy này không tự bật lại khi app trở lại.
3. Given maintain đang bật và app mất heartbeat, then helper tiếp tục hysteresis; ở/below lower phải cho sạc lại.
4. Given user Quit bình thường, then hành vi quạt/pin đúng quyết định PO ở mục 9 và UI cảnh báo trước nếu thao tác làm thay đổi policy.
5. Given helper cũng crash, then khi launch lại phải re-probe trước khi restore; trạng thái không verify được phải fail-safe, không báo success.

### US-08 — Bảo vệ quá nhiệt

**Là** người dùng, **tôi muốn** safety override mọi cấu hình thủ công khi máy quá nóng, **để** ưu tiên bảo vệ phần cứng.

**AC**

1. Given fan không ở System và nhiệt vượt ngưỡng liên tục đủ hold time, then helper chuyển fan System dù app/XPC không hoạt động.
2. Given thermal trip, then force discharge bị tắt và safety event được log.
3. Given một lần đọc nhiệt lỗi, then không đổi fan vô cớ; given mất telemetry kéo dài theo ngưỡng được duyệt, then helper chuyển degraded/System.
4. Given nhiệt giảm, then app không tự khôi phục Quiet/Custom; người dùng phải chủ động chọn lại.
5. Given safety override, then UI snapshot kế tiếp hiển thị System và lý do dễ hiểu.

### US-09 — Restore an toàn

**Là** người dùng gặp lỗi, **tôi muốn** một thao tác Restore rõ ràng, **để** đưa máy về điều khiển mặc định.

**AC**

1. Given helper connected, when Restore, then quạt System/Ftst release, maintain off, force discharge off và charging on.
2. Then thao tác có pending và kết quả xác nhận; gọi lặp lại vẫn cho cùng trạng thái cuối.
3. Given một phần restore lỗi, then không báo hoàn tất toàn bộ; UI chỉ rõ phần chưa xác minh và đề nghị retry.

## 7. Yêu cầu phi chức năng và phép đo nghiệm thu

### Hiệu năng/điện năng

- Đo Release build, không gắn debugger, cùng một máy chuẩn, cùng điều kiện AC/battery và workload.
- Ghi baseline bản hiện tại và bản tối ưu bằng Instruments (Time Profiler/Energy Log hoặc công cụ tương đương).
- Ba kịch bản bắt buộc, mỗi kịch bản 10 phút: UI hidden idle; menu open; dashboard + chart open.
- Báo cáo: CPU trung bình/p95, wakeups, số XPC request/phút, số SMC read/phút, memory ổn định và Energy Impact.
- Không chấp nhận nếu bản tối ưu làm tăng crash, tăng helper tick latency hoặc bỏ lỡ safety fallback.

### Ổn định

- Không crash/hang qua 20 chu kỳ sleep/wake liên tiếp.
- Helper kill/restart 10 lần: app đều phát hiện, disable control và tự reconnect.
- Không có hơn một request cùng loại đang chạy; memory không tăng liên tục qua bài soak 2 giờ.

### Tương thích/UX

- macOS 14+ Apple Silicon theo phạm vi hiện hành.
- Các trạng thái Connected, Reconnecting, Needs Approval, Error, Restoring phân biệt rõ; color không là tín hiệu duy nhất.
- Error không spam modal; thông báo có hành động Retry, Restore hoặc mở quyền hệ thống tùy nguyên nhân.
- Tiếng Việt và English có đầy đủ copy mới.

## 8. Ngoài phạm vi đợt này

- Fan curve theo nhiệt, lịch chạy, profile tự động.
- Remote/iPhone, cloud telemetry, analytics.
- Mở rộng Intel hoặc family SMC mới chưa có máy kiểm thử.
- Thiết kế lại toàn bộ UI hoặc thêm biểu đồ lịch sử dài hạn.
- Thay đổi các hardware timing reverse-engineered nếu không có test matrix máy thật.

## 9. Quyết định cần anh Phúc xác nhận trước khi Tech Lead chốt giải pháp

1. **Khi Quit bình thường:**
   - **Khuyến nghị BA:** quạt về System ngay; tắt force discharge; giữ Maintain Charge để bảo vệ pin.
   - Phương án khác: Restore toàn bộ, tức cho sạc đầy khi app đóng.
2. **Khi app crash/mất heartbeat:**
   - **Khuyến nghị BA:** quạt System, force discharge off, Maintain Charge tiếp tục độc lập trong helper.
3. **Khi thermal safety trip:**
   - **Khuyến nghị BA:** fan System + force discharge off; giữ charge maintain hiện tại. Có muốn tạm inhibit charging để giảm nhiệt hay không cần Tech Lead đánh giá rủi ro theo sensor/hardware.
4. **Thời gian fan fail-safe:** đề xuất giảm từ 45 giây xuống **15 giây**; cần test FTST/XPC trên các máy thật trước khi duyệt.
5. **Miền charge limit:** xác nhận upper tối thiểu là 20% hay nâng lên mức an toàn sản phẩm (đề xuất 40%); trong mọi trường hợp lower không được thành 18% ngoài miền công bố.
6. **Mục tiêu energy:** xác nhận ngưỡng CPU app idle <0,5% và chấp nhận số đo wakeups theo baseline phần cứng thay vì cam kết tuyệt đối trên mọi máy.

## 10. Definition of Done cho đợt tối ưu

- Anh Phúc phê duyệt 6 quyết định ở mục 9.
- Hoàng lập thiết kế kỹ thuật/tracing matrix BR → FR → test case, không thay đổi yêu cầu safety nếu chưa xin xác nhận.
- Dev có automated tests cho scheduler/poll coalescing, XPC state machine, stale data, command sequencing, fan/battery fail-safe; hardware path có test thủ công trên máy thật.
- Trâm chạy đầy đủ functional, sleep/wake, helper crash/restart, timeout, thermal simulation hợp lệ và regression.
- Nam build Release, kiểm tra warning/runtime log, đóng gói và cung cấp báo cáo benchmark trước/sau.
- Chỉ bàn giao khi toàn bộ Must pass; mọi ngoại lệ phải được anh Phúc chấp thuận bằng văn bản.
