# Phase tiếp theo — Thermal Control

Vòng 1 (P0–P11) **đã có source**. Phase này không viết lại app. Thứ tự: **ổn định máy thật → cứng helper → tính năng vòng 2**.

Thắng khi lệch: `THERMAL_CONTROL_TONG_HOP.md` Phần 1–2.

---

## Hiện trạng

| Phase | Việc | Status |
|---|---|---|
| P0–P11 | Skeleton → UI + helper + script | Source xong, **chưa verify trên Mac** |
| P12 | Harden vòng 1 sau build thật | **Làm ngay** |
| P13 | Persist + launch at login | Vòng 2a |
| P14 | Nhiệt độ trên UI | Vòng 2a |
| P15 | Fan curve (smctl-style, tối giản) | Vòng 2b |
| P16 | Lịch / schedule | Vòng 2b |
| P17 | Settings + EN | Vòng 2c |
| P18 | Packaging / notarize | Khi ổn định |
| — | Intel, iPhone, telemetry, App Store | **Không làm** |

Không nhảy P15 khi P12 chưa pass checklist máy thật.

---

# P12 — Harden vòng 1 (1–3 ngày trên Mac)

Mục tiêu: 10 mục checklist Phần 1.6 đều xanh.

### P12.1 Verify SMC trên máy

DoD:

- `sudo ThermalControlHelper --probe` in `fans=` + family pin
- Quiet đổi `F0Ac` trong 10s
- System + `Ftst==0` nếu key có
- Sleep 30s wake: policy còn
- `B0AC` phản ánh 70–80

Ghi log máy: chip (M1/M3/M4/M5), `FNum`, modeKey `Md` hay `md`, có `Ftst` không.

### P12.2 Lỗi compile / XPC hay gặp

Sửa nếu Xcode báo:

- `IORegisterForSystemPower` signature / `Unmanaged`
- `decodeArrayOfObjects` trên macOS 14
- `MenuBarExtra` window không inject `environmentObject` — gắn `.onAppear { vm.start() }` đã có
- Helper Team ≠ App Team → nới auth khi `ownTeams()` rỗng (đã có) + log Team ID

### P12.3 Install UX

- Script tìm helper tự nếu không truyền path
- App hiện đường dẫn `install_helper.sh` khi SMAppService fail
- Uninstall gọi restore **trước** bootout (script hiện `--probe` chưa restore; sửa helper nhận `--restore`)

### P12.4 Persist policy trong daemon (tối thiểu)

Vòng 1 mất Quiet sau reboot helper. P12: file `/Library/Application Support/ThermalControl/state.json` (root):

```json
{ "fan": "quiet|max|manual|system", "rpm": 2500, "maintain": true, "upper": 80, "lower": 70, "discharge": false }
```

Load lúc `HelperDelegate.init` rồi `apply()`. Không cần UI settings.

DoD: reboot máy, Quiet + 70–80 còn.

---

# P13 — Mở app lúc đăng nhập (nửa ngày)

- `SMAppService.mainApp().register()` hoặc Login Item app (không nhầm helper)
- Toggle dashboard: **Mở cùng macOS**
- Microcopy mới: `Mở lúc đăng nhập`

Không dùng `LSSharedFileList` cũ.

---

# P14 — Nhiệt độ trên UI (1 ngày)

TINH_NANG nói “xem nhiệt độ” nhưng vòng 1 chưa hiện số.

### Cách (smctl/OpenDente)

- **Đọc không cần helper:** thử keys `Tp01 Tp05 Te05 TC0P Ts0P` qua SMC read-only **nếu** user không root — thường fail. Thực tế AS đọc SMC cần helper.
- Thêm XPC `getTemps` → `[String: Double]`
- Panel: 1 dòng `Nhiệt: 78°C` (max các key đọc được)
- Dashboard: list 3–5 sensor
- Không chart

Cấm hiện tên key khó (`Tp0P`) trên panel nhỏ — map `CPU / Skin / SSD` nếu biết, không thì `Nhiệt đỉnh`.

Watchdog dùng cùng bộ key (đừng đọc 2 lần khác nhau).

---

# P15 — Fan curve tối giản (2–3 ngày)

Chỉ khi P12 pass. Học smctl, **không** TOML đầy đủ vòng 2.

### Hành vi

Policy mới `.curve` trong Helper:

```text
points: [(75°C, minRPM), (90, mid), (100, max)]
hysteresis 3°C
slew ≤ 400 RPM / tick
```

Tick 2s: đọc nhiệt đỉnh → interpolate → `enterManual` + `Tg`.

UI dashboard:

- Toggle **Tự theo nhiệt**
- 3 điểm cố định (không editor phức tạp)
- Quiet/Max/Manual tắt curve

Safety: trần nhiệt vẫn thắng curve.

Không: nhiều profile, file TOML user, `allow_below_minimum`.

XPC: `setFanCurveEnabled(Bool)` + `getFanCurve`.

---

# P16 — Lịch (1–2 ngày)

Use case: đêm Quiet, ngày System.

Helper timer 60s + calendar:

```text
[{ from: "22:00", to: "07:00", mode: quiet }]
```

UI: 1 rule thôi vòng 2. Conflict: user bấm Max tay → lịch pause đến slot sau **hoặc** override đến 1h — chọn **pause đến slot sau**, caption rõ.

Không: nhiều timezone, location.

---

# P17 — Settings + tiếng Anh (1 ngày)

- Tab Settings: timeout heartbeat (30–120s), trần nhiệt (không cho tắt guard), ngôn ngữ
- `Localizable.xcstrings` VI mặc định + EN
- Microcopy VI không đổi nghĩa

---

# P18 — Đóng gói

- Developer ID + notarize `Thermal Control.app` (helper đã embed)
- `install_helper.sh` trong `Contents/Resources/Scripts`
- Sparkle / update: **không** vòng 2
- Không App Store (sandbox cấm SMC)

---

## Việc cố ý chưa làm

- Auto boost theo app (Xcode, Compressor)
- Intel `FS!`
- Remote iPhone
- Telemetry
- Ép dưới min RPM

---

## Prompt Build App (P12 trước)

```text
Continue ThermalControl from existing MVVM source.
Do P12 only first:
- Add helper --restore flag; uninstall script calls it before bootout
- Persist policy JSON under /Library/Application Support/ThermalControl/state.json
- Autodetect helper path in install_helper.sh
- XPC getTemps for P14 can be stubbed but prefer implement read of Tp*/Te*/TC0P
Do not start P15 curve until asked.
Keep Views bound to ThermalViewModel. Frozen Vietnamese copy.
```

---

## Prompt P13–P15 (sau khi P12 xanh)

```text
Implement P13 login item for the main app (not helper).
P14: menu bar + dashboard peak temperature via getTemps.
P15: single 3-point fan curve in helper with hysteresis + slew; UI toggle only.
Do not add TOML, Intel, iPhone, telemetry.
```

---

## Lịch gợi ý

| Ngày | Phase |
|---|---|
| 1 | Build Xcode + P12.1 trên máy |
| 2 | P12.2–12.4 persist + uninstall restore |
| 3 | P13 + P14 nhiệt |
| 4–5 | P15 curve nếu cần |
| sau | P16 lịch / P17 i18n / P18 ký |
