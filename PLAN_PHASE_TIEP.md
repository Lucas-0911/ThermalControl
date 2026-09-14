# PLAN PHASE TIẾP — sau P0–P11 (vòng 1)

Vòng 1 (`P0–P11`) = app cài được, quạt 4 mode, pin 70–80, watchdog.  
File này = **vòng 2 trở đi**. Không phá contract XPC cũ; chỉ **thêm** method / DTO.

Thứ tự thắng: `THERMAL_CONTROL_TONG_HOP.md` Phần 1–2 → file này.

Làm tuần tự. Không nhảy P16 khi P12 chưa xanh trên máy thật.

---

## Trạng thái giả định

Source hiện tại đã có skeleton P0–P11. Phase tiếp **không viết lại** SMC packet / Ftst / CH0B. Chỉ gắn thêm.

Cổng vào mỗi phase: checklist vòng 1 trên Mac thật vẫn pass (Quiet, System, 70–80, uninstall).

---

## P12 — Ổn định vòng 1 trên máy thật (1–2 ngày)

Mục tiêu: sửa lỗi field, không thêm nút.

Làm:

- Log helper: subsystem `com.thermalcontrol.helper` (`os_log`) — RPM set, Ftst, CH0B/CHTE, B0AC
- App hiện `lastError` đủ đọc (bỏ raw `SMC 0x82` trên panel; dashboard được thêm 1 dòng kỹ thuật)
- Slider manual dùng `minRPM…maxRPM` thật, không cứng 1000–7000
- Persist draft `manualRPM` / ngưỡng pin `UserDefaults` (app only)
- Helper persist policy RAM → file `/Library/Application Support/ThermalControl/state.json` (root) để **reboot KeepAlive không mất Quiet/70–80**
- Reconcile lúc helper start: đọc file → apply (giống smctl startup reconcile)
- Nút Cài helper: nếu SMAppService fail, copy lệnh `sudo install_helper.sh` vào clipboard + caption

DoD:

- Reboot máy: Quiet còn, maintain còn
- `log show --predicate 'subsystem == "com.thermalcontrol.helper"' --last 10m`
- Uninstall vẫn restore + xóa `state.json`

Không: curve, chart.

---

## P13 — Nhiệt độ lên UI (chỉ đọc)

Mục tiêu: user thấy nóng/mát. App đọc sensor **không cần helper** nếu được; fallback XPC `getTemps`.

Làm:

- Helper: `getThermalSnapshot` → `[{key, celsius}]` (Tp*, TC0P, Te05…)
- Menu bar: nếu có quạt hiện RPM; dashboard Section **Nhiệt** 3–5 số
- Không vẽ graph
- Watchdog dùng cùng nguồn số với UI

DoD: dashboard hiện ít nhất 1 nhiệt độ trên máy có sensor.

OSS: smctl sensors read-only không root — ưu tiên App đọc nếu SMC read user được; nhiều máy read `Tp*` cần helper.

---

## P14 — Settings tối thiểu (UIUX vòng 2)

Màn mới `SettingsView` (tab hoặc section dashboard), tiếng Việt.

Gồm:

- Timeout heartbeat (15 / 45 / 90s) — **gửi helper**, không chỉ UserDefaults
- Trần nhiệt (90–105, cap cứng 105, hotspot 110 không cho sửa)
- Bật/tắt persist policy qua reboot
- Hiện version app + helper

Cấm: tắt thermal guard.

XPC thêm: `getSafetyConfig` / `setSafetyConfig`.

DoD: đổi timeout 15s, quit app, quạt về System sớm hơn 45s.

---

## P15 — Fan curve (policy trong helper, như smctl)

Đây là phase lớn nhất vòng 2.

Model (helper sở hữu):

```text
FanCurve
  name
  points: [(tempC, rpm | "min" | "max")]
  sensors: [key]
  hysteresisC
  slewRPMPerSec
```

XPC:

- `listCurves` / `setActiveCurve(name)` / `setCurve(FanCurveDTO)` / `clearCurve`

Hành vi (copy smctl, tự viết):

- Mode mới UI: **Curve** cạnh System / Quiet / Max
- Helper mỗi 1s: đọc sensor → temp + hysteresis → target → slew → `enterManual` + `F{n}Tg`
- Curve active = policy `.curve` ; Restore / System xóa active
- Thermal guard vẫn thắng curve
- 3 curve sẵn: `quiet-office` / `work` / `render` (điểm mặc định, user sửa được ở dashboard)

UI vòng 2:

- Dashboard: picker curve + bảng điểm (temp → RPM), không editor TOML
- Không file `/etc/smctl/config.toml` — JSON của ta

DoD:

- Chọn `work`, thổi máy (export video / stress) RPM lên theo điểm
- Hạ tải, RPM xuống có hysteresis (không giật)
- System tắt curve

Chưa làm: lịch giờ, per-app.

---

## P16 — Lịch + per-app boost

Sau P15 ổn.

**Lịch:** Quiet đêm 23:00–07:00, Curve `work` ban ngày. Helper timer; app chỉ gửi rule.

**Per-app:** whitelist bundle (`com.apple.dt.Xcode`, Final Cut…). Helper không thấy tên app user — App poll `NSWorkspace.runningApplications` rồi `setBoost(true/false)`. Helper: boost = Max hoặc curve `render` đến khi App bảo tắt + 30s grace.

DoD: mở Xcode → quạt lên; quit Xcode 30s → về curve/lịch.

---

## P17 — Pin nâng cao

- Preset 60–70 / 70–80 / 80–90
- “Sạc đầy tối nay một lần” (override maintain đến 100%, 04:00 hôm sau tự về)
- Cảnh báo caption khi force discharge
- Không đụng MagSafe LED / notch

DoD: bật “đầy tối nay”, 100% được; sáng hôm sau lại 80.

---

## P18 — Đóng gói Developer ID

- `export` Release 2 binary
- Notarize (nếu có tài khoản Developer trả phí)
- Script `package.sh` → zip `Thermal Control.app` + `install_helper.sh`
- Hardened runtime đã bật
- Không App Store, không sandbox

Không có tài khoản $99: giữ Personal Team + sudo script.

---

## P19 — i18n EN + a11y

- `Localizable.xcstrings` VI mặc định, EN
- VoiceOver đã có P10 — bổ sung Settings / Curve
- Không đổi meaning microcopy VI

---

## P20 — Cố ý chưa làm (backlog, không estimate)

- Intel `FS!`
- iPhone remote / widget
- Telemetry / account
- RGB, GPU power, DDC màn
- Ép dưới min
- Fan curve TOML tương thích smctl 1-1
- Copy code OpenDente (GPL)

---

## Thứ tự sprint đề xuất

```text
P12 ổn định + persist     ← làm ngay sau khi build được trên Mac
P13 nhiệt độ UI
P14 settings an toàn
P15 fan curve             ← giá trị lớn
P16 lịch / per-app
P17 pin overnight
P18 ký phát hành
P19 EN
```

Một sprint ~ P12+P13. P15 riêng một sprint.

---

## XPC thêm (gộp, không phá method cũ)

```text
getThermalSnapshot
getSafetyConfig / setSafetyConfig
getPersistedState / setPersistedState   // hoặc helper tự file
listCurves / setActiveCurve / upsertCurve / clearCurve
setSchedule([Rule])
setAppBoost(Bool)
setOvernightFullCharge(Bool)
```

Version protocol: thêm `protocolVersion: Int` vào `Capabilities` (=2 từ P13). App cũ bỏ qua field mới.

---

## Folder mới (từ P14)

```text
App/Views/SettingsView.swift
App/Views/Components/CurveEditor.swift
App/Views/Components/TempPanel.swift
Helper/FanCurveEngine.swift
Helper/ScheduleEngine.swift
Helper/StateStore.swift          // state.json
Shared/Models/{TempReading,FanCurve,SafetyConfig,ScheduleRule}.swift
```

MVVM giữ: View không gọi XPC.

---

## Prompt Build App (phase tiếp)

```text
Continue ThermalControl from existing MVVM source.
Do not rewrite P0–P11 SMC/Ftst/CH0B.

Implement the next phases in PLAN_PHASE_TIEP.md starting at P12.
Stop at the end of the phase I name (default: finish P12 then P13).
Keep Vietnamese UI copy.
Add XPC methods; do not break old ones.
Persist helper policy to /Library/Application Support/ThermalControl/state.json.
Uninstall must delete state and restore hardware.
```

---

## Việc bạn làm trên Mac trước P12

1. Build + `sudo install_helper.sh` theo hướng dẫn Xcode  
2. Ghi 5 dòng: máy (M mấy), Quiet có giảm RPM không, 70–80 mA có về 0 không, reboot có mất helper không, lỗi đỏ nếu có  
3. Nhắn “làm P12” hoặc “làm P12+P13”
