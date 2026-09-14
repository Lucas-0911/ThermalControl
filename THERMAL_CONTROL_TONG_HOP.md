# Thermal Control — Tài liệu tổng hợp (một file)

App menu bar macOS: quạt + giới hạn sạc pin trên Apple Silicon.

Dùng file này cho **Build App**. Khi lệch trong chính file: **Phần 1 Tính năng → Phần 2 UI/UX → Phần 3 ERD → Phần 4–6 Kỹ thuật**.

Không copy nguyên open-source. GPL (OpenDente) chỉ học hành vi.

---

# Phần 0 — Phạm vi vòng 1

Đối tượng: Mac Apple Silicon, macOS 14+.

Làm:

- Menu bar xem RPM / % pin
- Quạt: System / Quiet / Max / Manual (clamp min–max)
- Pin (nếu có): 70–80, cho/ngắt sạc, force discharge ở dashboard
- Restore hệ thống
- Helper root + XPC; cài admin một lần
- Watchdog: mất app ~45s hoặc quá nhiệt → quạt System
- Sleep/wake helper apply lại

Không làm vòng 1:

- Fan curve / lịch / auto boost
- Intel Mac, RGB, GPU power
- iPhone remote, cloud, telemetry
- Ép RPM dưới min
- App Store, sandbox, setuid helper
- Onboarding, chart, UI tiếng Anh

---

# Phần 1 — Tính năng đầu ra

## 1.1 Sản phẩm

App chạy nền. Không cần cửa sổ luôn mở.

1. Xem quạt / pin trên menu bar
2. Chỉnh quạt
3. Giới hạn sạc MacBook
4. Một nút trả máy về macOS

## 1.2 Lần đầu

- Icon quạt trên menu bar
- Chưa helper: “Chưa kết nối helper”, CTA cài, **không crash**
- Không quạt → ẩn quạt
- Không pin (mini/Studio) → ẩn pin

## 1.3 Quạt

| Việc | Đầu ra |
|---|---|
| Xem | RPM, min, max, cập nhật vài giây |
| System | macOS quản lý |
| Quiet | về min |
| Max | về max |
| Manual | slider + Set, trong min–max |
| Restore | mọi quạt System |

Lỗi phải hiện chữ, không im. App chết ~45s → quạt System. Nóng quá → quạt System.

## 1.4 Pin (chỉ khi có pin)

| Việc | Đầu ra |
|---|---|
| Xem | %, AC, mA (sự thật đang sạc) |
| Giữ 70–80 | ≥80 ngắt, ≤70 sạc lại |
| Ngưỡng tự chọn | dashboard lower/upper |
| Cho sạc / Ngắt sạc | |
| Force discharge | dashboard, mặc định tắt |
| Restore | bỏ limit, cho sạc |

`pmset` có thể vẫn “charging” — UI nhìn **mA**. Gỡ helper không được khoá sạc vĩnh viễn.

## 1.5 Vận hành

Helper KeepAlive sau reboot. Gỡ bằng script. Không App Store.

## 1.6 Checklist máy thật

1. Icon menu bar
2. sudo helper → chấm xanh, RPM hoặc %
3. Quiet giảm RPM
4. System trả quạt
5. MacBook 70–80 → mA ~0 khi gần upper
6. Quit ~1 phút → quạt System
7. uninstall → sạc/quạt bình thường
8. Không helper không crash
9. Fanless / desktop ẩn đúng khối
10. XPC lạ không làm chết helper

---

# Phần 2 — UI/UX

Nền: SwiftUI, MenuBarExtra `.window`, tiếng Việt, light/dark hệ thống.

## 2.1 Nguyên tắc

1. Menu bar chính, cửa sổ phụ
2. Bấm là thấy kết quả trong 2s hoặc thấy lỗi
3. Max / force discharge / mất helper khác màu
4. Ẩn khối không có phần cứng
5. Không chữ `CHTE` / `Ftst` trên panel nhỏ

## 2.2 Cây màn hình

```text
Icon menu bar
 └── Panel 360pt
      Header · Helper · Quạt · Pin · Lỗi · Footer
Cửa sổ Thermal Control ~520×420
      Helper · Quạt · Pin · An toàn
```

Không onboarding.

## 2.3 Icon

| Tình huống | Label | Symbol |
|---|---|---|
| Có quạt, đã nối | `2400` | `fan` |
| Không quạt, có pin | `78%` | `battery.75` |
| Chưa helper / lỗi | `TC` | `fan` |

Không animate.

## 2.4 Panel 360pt

Padding 14, spacing 12, divider.

**Header:** Thermal Control + caption + chấm 10pt (xanh connected, cam còn lại).

Caption: `Helper đang chạy` · `Chưa kết nối helper` · `Helper v1.0.0` · `Cần duyệt Login Items`

**Helper:** `Helper: enabled|requiresApproval|notRegistered|notFound`  
Nút: Cài helper (prominent khi chưa nối) · Login Items · Kết nối lại

**Quạt:**  
`Fan 0: 2410 RPM  (min 1200 – max 6200)`  
`[ System ] [ Quiet ] [ Max ]` — Max cam. Slider + `Set 2500`.  
Empty: `Không phát hiện quạt (hoặc helper chưa chạy).`

**Pin:**  
`78%  •  0 mA  •  đang cắm`  
`[ Giữ 70–80 ] [ Cho sạc ] [ Ngắt sạc]`  
Empty: `Không có pin nội bộ (Mac mini / Studio) — chỉ dùng quạt.`

**Lỗi:** caption đỏ, tối đa 3 dòng. Generic: `Không gửi được lệnh. Kiểm tra helper.`

**Footer:** Mở cửa sổ · Khôi phục hệ thống · Quit

## 2.5 Dashboard Form

Helper: status, SMAppService, fan/battery Có-Không. Nút đăng ký / Login Items / Refresh.  
Quạt: list + System Quiet Max Manual.  
Pin: ẩn nếu không có. Slider lower/upper. Toggle Force discharge + caption:  
`Vừa cắm nguồn vừa giảm % pin. Tắt nếu không hiểu tác dụng.`  
An toàn: caption heartbeat/nhiệt/sleep + Restore tất cả.

## 2.6 State

`disconnected | connecting | connected | needsApproval | error | restoring`  
fanless = connected && fanCount==0  
desktop = connected && !batteryPresent  
disconnected → disable Quiet/Max/Set/70–80

Optimistic UI: đổi nút mode ngay, rollback nếu fail.  
Poll 3s. Slider draft không bị poll đè.  
Không confirm, không sound, không chart.

## 2.7 Microcopy đóng băng

Cài helper · Login Items · Kết nối lại · Mở cửa sổ · Khôi phục hệ thống · Quit · Quạt · Pin · An toàn · System · Quiet · Max · Set · Giữ 70–80 · Cho sạc · Ngắt sạc · Force discharge · Restore tất cả · Helper đang chạy · Chưa kết nối helper · Không phát hiện quạt (hoặc helper chưa chạy). · Không có pin nội bộ (Mac mini / Studio) — chỉ dùng quạt.

## 2.8 Màu / a11y

Accent hệ thống. Xanh chỉ chấm. Cam = Max + force on. Đỏ chỉ chữ lỗi. Số monospaced. Nút có chữ. VoiceOver: `Quạt 0, 2410 vòng/phút`.

---

# Phần 3 — ERD / miền

Không có SQL. Domain:

```text
APP 1 — 0..1 XPC_SESSION — 1 HELPER
HELPER 1 — 0..n FAN_CHANNEL
HELPER 1 — 0..1 BATTERY
FAN_CHANNEL n — 1 FAN_POLICY (system|quiet|max|manual)
BATTERY 1 — 0..1 CHARGE_POLICY
FAN/BATTERY — n SMC_KEY
APP — HEARTBEAT → WATCHDOG
```

Invariant:

- App không đụng SMC_KEY
- Policy chỉ Helper persist (RAM daemon)
- FNum=0 ⇒ ẩn quạt
- !batteryPresent ⇒ ẩn pin
- Timeout heartbeat chỉ restore quạt
- Restore đầy đủ mới bỏ charge policy

Use case: UC1 cài helper · UC2 đọc cảm biến · UC3 quạt · UC4 pin · UC5 restore · UC6 sleep re-apply · UC7 heartbeat · UC8 quá nhiệt

---

# Phần 4 — Open-source bám theo

| Repo | Lấy | Không lấy |
|---|---|---|
| leaperone/smctl | Policy trong daemon, XPC+Team ID, verify write, LE int, restore lúc chết, IORegisterForSystemPower, nhiệt 100/105/110, Ftst refcount, không setuid, không ghi charge-enable khi adapter-cut | CLI, TOML curve, alert, DDC |
| agoodkind/macos-smc-fan | Packet SMC, Ftst, M1–M5 | Accept mọi XPC |
| exelban/stats + MacFanControl | Direct mode trước, Ftst+3s+retry, F{n}md M5 | Intel FS! |
| OpenDente | Layout App+Helper+Shared+XcodeGen, IOKit pin ở app, probe CH0/CHTE | Copy code GPL |
| HelperToolApp | SMAppService.daemon(plist kèm .plist) | |
| AlDente | CH0B=0x02 inhibit, 0x00 allow | SMJobBless |
| Fanny | — | setuid +s |

Sửa so với draft cũ:

- Không hardcode inhibit=1; thử 0x02 rồi 0x01, nhìn B0AC
- Power notifier bắt buộc
- Auth XPC không Int32(gid) checked
- Đọc sensor không cần helper
- Hai đường cài: SMAppService + sudo script

---

# Phần 5 — Kiến trúc & folder

```text
View → ThermalViewModel → Services → XPC → Helper(root) → AppleSMC
```

| Tầng | Được | Cấm |
|---|---|---|
| View | UIUX, intent VM | IOKit, XPC, SMAppService, chữ SMC |
| ViewModel | state, map DTO | packet SMC |
| Service | XPC, IOKit đọc pin, register helper | @Published UI |
| Helper | SMC, policy, watchdog | SwiftUI |

```text
ThermalControl/
├── THERMAL_CONTROL_TONG_HOP.md
├── project.yml
├── Shared/Constants.swift
├── Shared/Models/{FanMode,FanChannel,FanStatus,BatteryStatus,Capabilities}.swift
├── Shared/XPC/ThermalHelperProtocol.swift
├── App/ThermalControlApp.swift
├── App/Models/HelperConnectionState.swift
├── App/Services/{XPCClient,SensorReader,HelperInstallService}.swift
├── App/ViewModels/ThermalViewModel.swift
├── App/Views/{MenuBarView,DashboardView}
├── App/Views/Components/{FanPanel,BatteryPanel,HelperStatusRow}.swift
├── Helper/{main,XPCListener,SMCService,FanController,BatteryController,SafetyWatchdog,PowerObserver}.swift
├── Helper/{Info.plist,ThermalControlHelper.entitlements,com.thermalcontrol.helper.plist}
└── Scripts/{install_helper.sh,uninstall_helper.sh}
```

IDs: `com.thermalcontrol.app` · `com.thermalcontrol.helper` (mach trùng)  
Sandbox false. LSUIElement true. macOS 14.

---

# Phần 6 — Contract kỹ thuật

## 6.1 ViewModel

State: connectionState, helperStatusText, smAppServiceState, lastError, fans, desiredFanMode, manualRPM (draft), batteryPresent/percent/amperageMA/externalAC, chargeUpper/Lower, chargingEnabled, maintainActive, forceDischarge.

Intent: start refresh reconnect installHelper openLoginItems setFanMode setManualRPM setMaintain70_80 setChargeLimit setChargingEnabled setForceDischarge restoreSystem openDashboard quitApp.

Heartbeat 5s. Poll 3s.

## 6.2 XPC

ping · getCapabilities · getFanStatus · setFanMode · setFanTargetRPM · getBatteryStatus · setChargeLimit · setChargingEnabled · setForceDischarge · restoreSystemControl

DTO NSObject + NSSecureCoding.

Auth: SecCode PID → Team ID + bundle allowlist. Fail: invalidate, return false, không trap.

## 6.3 SMC

IOKit AppleSMC method 2. info=9 read=5 write=6. Key ASCII 4 byte. flt + integer **LE** trên arm64. Một serial queue. Verify + settle 200–500ms.

## 6.4 Fan (Stats / macos-smc-fan / smctl)

```text
modeKey = F{n}Md else F{n}md
Ftst optional (M5 không có)

enterManual: write mode=1
  else if Ftst: Ftst=1, ref++, sleep 3s, retry 0.1s / 10s, rồi F{n}Tg clamp
leave: mode=0; ref-- ; ref==0 && Ftst==1 → Ftst=0
Quiet=Mn  Max=Mx  System=leave all
```

## 6.5 Battery (OpenDente / smctl / AlDente)

```text
family = CHTE|CHIE ? tahoe : CH0B|CH0C ? legacy : none
inhibit: legacy thử 0x02 rồi 0x01; không enable charge khi CHIE đang cut
truth = B0AC > 20mA
tick 2s: %>=upper inhibit; %<=lower allow
forceDischarge CH0I/CHIE, re-assert mỗi tick
```

## 6.6 Watchdog + power

IORegisterForSystemPower → apply fan+battery.  
Nhiệt 1–2s: trần 100, cap 105, Tp* 110; mất sensor khi manual = unsafe.  
Heartbeat 45s → quạt System.  
Exit/uninstall: quạt System + cho sạc + tắt discharge.

## 6.7 Cài helper

A. `SMAppService.daemon(plistName: "com.thermalcontrol.helper.plist")` + Login Items.  
Plist: BundleProgram `Contents/MacOS/ThermalControlHelper`, MachServices, AssociatedBundleIdentifiers, KeepAlive.

B. Script: `/Library/PrivilegedHelperTools/ThermalControlHelper` + LaunchDaemons + bootstrap. Uninstall restore trước bootout.

---

# Phần 7 — Phase build (P0–P11)

| P | Làm | DoD |
|---|---|---|
| 0 | XcodeGen, plist, entitlements | generate được project |
| 1 | DTO + protocol | NSSecureCoding |
| 2 | SMCService | `--probe` in FNum |
| 3 | Capabilities | 2 họ pin + Md/md |
| 4 | FanController | 4 mode + Ftst refcount |
| 5 | BatteryController | 70–80 + B0AC |
| 6 | PowerObserver + Watchdog | wake + nhiệt |
| 7 | XPC + auth + restore exit | không crash khi reject |
| 8 | App services | transport only |
| 9 | ViewModel | state phần 2.6 |
| 10 | Views | 360pt + dashboard + microcopy |
| 11 | Scripts + README build | sudo install chạy |

Không P10 trước P9. Không XPC trong View.

---

# Phần 8 — Build trên Mac

```bash
brew install xcodegen
cd ThermalControl
xcodegen generate
open ThermalControl.xcodeproj
# Signing: Team cho CẢ 2 target
# Scheme ThermalControl · Destination My Mac · ⌘B

HELPER=$(ls -d ~/Library/Developer/Xcode/DerivedData/ThermalControl-*/Build/Products/Debug/ThermalControlHelper | head -1)
sudo bash Scripts/install_helper.sh "$HELPER"
```

Gỡ:

```bash
sudo bash Scripts/uninstall_helper.sh
```

Lỗi thường: chưa Team; chưa sudo helper; 0x82 chờ Ftst 3–10s; mini không pin.

---

# Phần 9 — Prompt Build App (dán nguyên)

```text
Create a NEW macOS app ThermalControl from THERMAL_CONTROL_TONG_HOP.md (single spec).

Priority: Phần 1 features > Phần 2 UI/UX frozen Vietnamese copy > Phần 3 ERD > Phần 4–6 implementation.

OSS behavior (do not copy GPL source):
- smctl: policy-in-daemon, XPC Team ID auth, LE ints, verified writes,
  restore on exit, IORegisterForSystemPower, thermal 100/105/110,
  Ftst refcount, no setuid, never charge-enable while adapter-cut.
- macos-smc-fan / Stats / MacFanControl: direct mode first, Ftst+3s+retry,
  probe F{n}Md and F{n}md, M5 may lack Ftst.
- OpenDente: menu bar + helper + XcodeGen; IOKit battery read in app;
  probe CH0B/CH0C vs CHTE/CHIE.
- HelperToolApp: SMAppService.daemon(plistName with .plist).
- AlDente inhibit often CH0B=0x02; verify with B0AC.
Also ship Scripts/install_helper.sh.

MVVM: Views bind ThermalViewModel only.
Phases P0–P11. No items from "Không làm vòng 1".
After P11 list files and Mac build commands.
```

---

# Phần 10 — Clone đọc (không vendor vào app)

```bash
git clone --depth 1 https://github.com/leaperone/smctl
git clone --depth 1 https://github.com/agoodkind/macos-smc-fan
git clone --depth 1 https://github.com/killerk3emstar/OpenDente
```
