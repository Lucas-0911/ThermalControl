# PLAN — Build App mới: Thermal Control

Spec duy nhất để **Build App**. App mới, Xcode + SwiftUI + Helper.

Đọc kèm (bắt buộc, không mâu thuẫn file này):

| File | Vai trò | Khi lệch |
|---|---|---|
| `TINH_NANG.md` | Đầu ra sản phẩm, checklist xong | Tính năng thắng plan kỹ thuật |
| `UIUX.md` | Layout, state UI, microcopy đóng băng | UI thắng plan |
| `ERD.md` | Entity / cardinality / use case | Model thắng nếu đặt sai quan hệ |
| `PLAN.md` (file này) | Folder MVVM, phase code, helper SMC | Cách implement |

Không thêm mục “không làm vòng 1” trong `TINH_NANG.md` / `UIUX.md`.

---

## 0. Sản phẩm vòng 1 (rút từ TINH_NANG)

Menu bar macOS 14+ Apple Silicon:

1. Icon: RPM quạt 0, hoặc `%` pin, hoặc `TC` khi chưa nối.
2. Quạt: System / Quiet / Max / Manual RPM (clamp min–max).
3. Pin (nếu có): xem % + mA; nút Giữ 70–80; Cho sạc; Ngắt sạc; Force discharge chỉ trên dashboard.
4. Restore hệ thống.
5. Chưa helper: không crash, CTA cài, control disable.
6. Fanless → ẩn quạt. Desktop không pin → ẩn pin.
7. Watchdog: mất app ~45s hoặc quá nhiệt → quạt về System.
8. Cài helper: script `sudo` là đường chính; SMAppService là phụ.

UI tiếng Việt, copy đúng `UIUX.md` mục 7.

---

## 1. Kiến trúc MVVM

```text
View (SwiftUI)          ← chỉ bind VM, copy UIUX
    ↓ intent
ThermalViewModel        ← state UIUX mục 6 + intent TINH_NANG
    ↓
Services                ← XPCClient, SensorReader, HelperInstallService
    ↓ XPC
Helper (root, không MVVM)
    SMCService · FanController · BatteryController · SafetyWatchdog
```

| Tầng | Được | Cấm |
|---|---|---|
| View | Layout UIUX, gọi intent VM | IOKit, NSXPC, SMAppService, chữ SMC key |
| ViewModel | State, map DTO → UI, lastError tiếng Việt | Packet SMC, SwiftUI besides binding |
| Shared Model | DTO NSSecureCoding, protocol | SwiftUI |
| Service | XPC, đọc pin IOKit, register daemon | `@Published` UI |
| Helper | SMC, policy, watchdog | SwiftUI |

ERD: App **không** quan hệ thẳng `SMC_KEY`. View chỉ bind DTO.

---

## 2. Folder app mới

```text
ThermalControl/
├── PLAN.md
├── TINH_NANG.md
├── UIUX.md
├── ERD.md
├── README.md
├── HUONG_DAN_BUILD.md
├── project.yml
├── Shared/
│   ├── Constants.swift
│   ├── Models/
│   │   ├── FanMode.swift
│   │   ├── FanChannel.swift
│   │   ├── FanStatus.swift
│   │   ├── BatteryStatus.swift
│   │   └── Capabilities.swift
│   └── XPC/ThermalHelperProtocol.swift
├── App/
│   ├── ThermalControlApp.swift
│   ├── Info.plist
│   ├── ThermalControl.entitlements
│   ├── Models/HelperConnectionState.swift
│   ├── Services/
│   │   ├── XPCClient.swift
│   │   ├── SensorReader.swift
│   │   └── HelperInstallService.swift
│   ├── ViewModels/ThermalViewModel.swift
│   └── Views/
│       ├── MenuBarView.swift
│       ├── DashboardView.swift
│       └── Components/
│           ├── FanPanel.swift
│           ├── BatteryPanel.swift
│           └── HelperStatusRow.swift
├── Helper/
│   ├── main.swift
│   ├── XPCListener.swift
│   ├── SMCService.swift
│   ├── FanController.swift
│   ├── BatteryController.swift
│   ├── SafetyWatchdog.swift
│   ├── Info.plist
│   ├── ThermalControlHelper.entitlements
│   └── com.thermalcontrol.helper.plist
└── Scripts/
    ├── install_helper.sh
    └── uninstall_helper.sh
```

IDs:

- App `com.thermalcontrol.app`
- Helper + mach `com.thermalcontrol.helper`
- Plist `com.thermalcontrol.helper.plist`
- Deployment macOS 14, sandbox **false**, `LSUIElement=true`

`project.yml` (XcodeGen): 2 target App + Helper tool.

---

## 3. State UI (HelperConnectionState)

Enum App-only, ViewModel publish:

```text
disconnected | connecting | connected | needsApproval | error | restoring
```

Kết hợp capability:

- `fanless` = connected && fanCount == 0 → ẩn FanPanel
- `desktop` = connected && !batteryPresent → ẩn BatteryPanel
- disconnected → disable Quiet/Max/Set/70–80; CTA Cài helper prominent

Chấm: xanh = connected; cam = còn lại (trừ error có dòng đỏ).

---

## 4. ThermalViewModel contract

Published:

```text
connectionState
helperStatusText
smAppServiceState
lastError: String?

fanCount, fans: [FanChannel]
desiredFanMode: FanMode
manualRPM: Int          // draft slider, không bị poll ghi đè
ftstPresent: Bool       // không hiện panel nhỏ

batteryPresent, batteryPercent, amperageMA
externalAC: Bool
chargeUpper, chargeLower
chargingEnabled, maintainActive, forceDischarge
```

Intents (đúng tên nút UIUX):

```text
start() refresh() reconnect()
installHelper() openLoginItems()
setFanMode(FanMode)          // system, quiet, max
setManualRPM()               // dùng manualRPM draft, index -1 = tất cả
setMaintain70_80()
setChargeLimit(upper:lower:)
setChargingEnabled(Bool)
setForceDischarge(Bool)
restoreSystem()
openDashboard()
quitApp()
```

Poll 3s + heartbeat 5s. Lỗi user-facing: `Không gửi được lệnh. Kiểm tra helper.`  
Raw SMC chỉ gắn thêm ở dashboard nếu cần.

Optimistic UI: đổi mode prominent ngay, rollback nếu reply false.

---

## 5. XPC protocol

```text
ping
getCapabilities
getFanStatus
setFanMode(Int)
setFanTargetRPM(rpm, fanIndex)
getBatteryStatus
setChargeLimit(upper, lower)
setChargingEnabled
setForceDischarge
restoreSystemControl
```

DTO = entity ERD: FanChannel, FanStatus, BatteryStatus, Capabilities. NSObject + NSSecureCoding.

---

## 6. Helper — miền ERD

**Probe lúc start**

- `FNum` → 0..n FanChannel
- `F{n}Ac Tg Mn Mx`
- Mode `F{n}Md` rồi `F{n}md`
- `Ftst` optional
- Battery family: `CHTE`/`CHIE` else `CH0B`/`CH0C` else none
- `B0AC` `B0AV`

**FanPolicy** (chỉ Helper giữ): system | quiet | max | manual(rpm, index?)

- Manual: direct mode=1; fail + có Ftst → Ftst=1, đợi 3s, retry; không Ftst thì fail rõ
- Clamp target [Mn, Mx]
- Restore: mode=0, Ftst=0

**ChargePolicy**

- Maintain: ≥ upper inhibit; ≤ lower cho sạc
- Inhibit convention: 1 = chặn
- Sự thật đang sạc: B0AC > 20 mA
- Desktop: không BATTERY entity

**Watchdog** 2s

- battery.tick()
- policy ≠ system → apply lại mỗi ~10s
- heartbeat > 45s → restore **chỉ quạt**
- nhiệt ≥105°C / 8s → restore quạt
- UC5 Restore đầy đủ: quạt System + bỏ maintain + cho sạc + tắt discharge

Auth XPC: Team ID; helper chưa sign thì cho local + log. Reject không crash.

---

## 7. UI implement (bám UIUX, không improvising)

- `MenuBarExtra` `.window`, panel width 360, padding 14
- Icon rules UIUX mục 3
- Panel khối: Header → HelperStatusRow → FanPanel → BatteryPanel → error → footer
- Dashboard Form 520×420: Helper, Quạt, Pin, An toàn
- Max button tint cam
- Force discharge chỉ dashboard + caption cảnh báo
- Microcopy **nguyên văn** UIUX mục 7
- Không onboarding, chart, EN, settings page, chữ CHTE/Ftst trên panel nhỏ

---

## 8. Scripts + docs ship cùng app

`install_helper.sh`: copy binary `/Library/PrivilegedHelperTools/ThermalControlHelper`, plist LaunchDaemon mach `com.thermalcontrol.helper`, bootstrap system, log `/tmp/thermalcontrol-helper.log`.

`uninstall_helper.sh`: bootout + xóa file.

`HUONG_DAN_BUILD.md`: xcodegen → ký 2 target → ⌘B → sudo install → mở app.

`README.md`: 15 dòng mục đích + link 4 tài liệu + cài/gỡ.

---

## 9. Phase Build App (làm đúng thứ tự)

| Phase | Làm | DoD |
|---|---|---|
| P0 | project.yml, plist, entitlements, Constants, copy 4 md vào repo | xcodegen ra 2 target |
| P1 | Shared Models + protocol | NSSecureCoding compile |
| P2 | SMCService | open/read/write + queue |
| P3 | Probe + Capabilities | FNum + family |
| P4 | FanController | 4 mode + restore |
| P5 | BatteryController | 70–80 + inhibit |
| P6 | Watchdog | 45s + thermal + reapply |
| P7 | XPCListener + main + auth | mach listen |
| P8 | App Services | XPCClient transport only |
| P9 | ThermalViewModel + HelperConnectionState | đủ contract mục 4 |
| P10 | Views đúng UIUX | 360pt panel + dashboard, ẩn khối |
| P11 | Scripts + README + HUONG_DAN_BUILD | user build được trên Mac |

Không làm P10 trước P9. Không nhét XPC vào View.

---

## 10. Definition of Done (khớp TINH_NANG mục 9)

Trên máy Mac thật sau build:

1. Icon menu bar khi mở app
2. sudo helper → chấm xanh, thấy RPM hoặc %
3. Quiet giảm RPM (máy có quạt)
4. System trả quạt
5. MacBook: 70–80 → mA ~0 khi gần upper
6. Quit app ~45–60s → quạt System
7. uninstall → hết daemon, sạc/quạt bình thường
8. App không helper không crash
9. Fanless / desktop ẩn đúng khối
10. Chữ nút = UIUX mục 7

---

## 11. Cấm

- App Store, sandbox, SIP off
- Intel `FS!` như mục tiêu
- Fan curve, lịch, auto boost, iPhone remote, telemetry
- Project thứ hai / đổi bundle id
- Hiện key SMC trên menu panel
- Confirm dialog vòng 1

---

## 12. Prompt dán vào Build App

```text
Create a NEW macOS app ThermalControl from PLAN.md.

Source of truth:
- TINH_NANG.md = features / done checklist
- UIUX.md = screens, states, frozen Vietnamese copy
- ERD.md = entities and cardinality
- PLAN.md = MVVM folders, phases P0–P11, helper behavior

Rules:
- App MVVM. Views bind ThermalViewModel only.
- Helper is root daemon, not MVVM.
- MenuBarExtra .window 360pt first; Dashboard second.
- Hide fan or battery when hardware absent.
- sudo Scripts/install_helper.sh is the real install path.
- Do not implement "không làm vòng 1" items.
- After P11 list every file and the exact Mac build commands.
```
