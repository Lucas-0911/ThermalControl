# PLAN BUILD CHI TIẾT — Thermal Control

App mới. Tài liệu thắng khi lệch: `TINH_NANG.md` → `UIUX.md` → `ERD.md` → file này.

Không copy nguyên repo. Lấy **cách làm đã kiểm chứng**, tự viết code.

---

## A. Audit spec hiện tại vs open-source (2026)

| Spec cũ của ta | Thực tế OSS | Sửa khi build |
|---|---|---|
| Inhibit `CH0B=1` | AlDente ghi `CH0B=0x02` để chặn, `0x00` để sạc. OpenDente/smctl probe + verify | **Không hardcode 1.** Write → đọc lại `B0AC`. Thử 0x01 rồi 0x02 nếu dòng sạc chưa về 0 |
| Watchdog chỉ timer 10s | smctl + macfan: `IORegisterForSystemPower` vì sleep **xóa Ftst** | Bắt buộc power notifier, timer chỉ là lớp 2 |
| Thermal 105°C cứng | smctl: trần 100°C, cap 105, hotspot `Tp*` cho tới 110; **không tắt được** | Copy ngưỡng này |
| Ftst clear mỗi lần restore 1 quạt | smctl: Ftst **global**, refcount — quạt manual cuối mới `Ftst=0` | Làm refcount |
| XPC reject được crash daemon | smctl PR#4: gid âm làm trap | Auth không `Int32(gid)` checked; reject return false |
| Integer SMC BE | Apple Silicon **LE** (`B0AV` sai nếu BE) | Decode theo arch |
| Đọc sensor qua helper | smctl/OpenDente: **đọc IOKit/SMC không cần root**; helper chỉ write | SensorReader ở App; Helper chỉ control |
| SMAppService là đủ | Personal Team hay `requiresApproval`; smctl vẫn có `daemon install` root | **Hai đường**: SMAppService + `install_helper.sh` |
| macos-smc-fan accept mọi XPC | smctl gọi đó là lỗ | Phải verify Team ID / audit token |
| Setuid helper (Fanny) | smctl: bài học battery/sudoers — **cấm setuid** | Chỉ LaunchDaemon |
| Ghi CHTE khi CHIE đang cắt | smctl: firmware **bật lại adapter** | Không ghi charge-enable khi force-discharge đang on |
| Fan curve TOML | smctl có, TINH_NANG cấm vòng 1 | Không làm curve |

Nguồn chính:

- [leaperone/smctl](https://github.com/leaperone/smctl) — daemon + XPC + safety + battery/fan policy
- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) — Ftst, M1–M5, packet SMC
- [killerk3emstar/OpenDente](https://github.com/killerk3emstar/OpenDente) — menu bar + helper + CH0/CHTE + XcodeGen
- [exelban/stats](https://github.com/exelban/stats) + [raminsharifi/MacFanControl](https://github.com/raminsharifi/MacFanControl) — direct-first rồi Ftst, `F{n}md` trên M5
- [alienator88/HelperToolApp](https://github.com/alienator88/HelperToolApp) — SMAppService, plist **có** `.plist`

---

## B. Việc lấy / không lấy

### Lấy

1. **smctl design:** policy nằm helper; app chỉ remote. XPC + audit token. Verify write. Uninstall/kill → restore fan **và** charging. Power sleep hook. Thermal guard không tắt.
2. **macos-smc-fan / Stats / macfan:**  
   `thử F{n}Md|md=1` → fail `0x82` + có `Ftst` → `Ftst=1` → đợi ~3s → retry 100ms đến ~10s → `F{n}Tg`. M5: không Ftst, mode lowercase.
3. **OpenDente layout:** `App/ + Helper/ + Shared/ + project.yml`. Đọc pin IOKit ở app. Probe 2 họ key pin.
4. **HelperToolApp:** `SMAppService.daemon(plistName: "….plist")`, helper trong `Contents/MacOS`, plist trong `Contents/Library/LaunchDaemons`, `BundleProgram`, `MachServices`.

### Không lấy

- CLI/TOML/alert/display DDC của smctl
- setuid / AppleScript `chmod +s` (Fanny)
- Unix socket như `batt`
- SMJobBless
- Copy file nguồn GPL (OpenDente GPL — **chỉ học hành vi**, không dán code)
- Fan control legacy Intel `FS!` như mục tiêu

---

## C. Kiến trúc đích (giống smctl, bọc GUI như OpenDente)

```text
Thermal Control.app  (unprivileged, SwiftUI MVVM)
  Views → ThermalViewModel → XPCClient
  SensorReader (IOKit pin + optional SMC read-only)

        XPC mach com.thermalcontrol.helper
        + SecCode Team ID

ThermalControlHelper  (root LaunchDaemon)
  IPC | FanPolicy | ChargePolicy | Watchdog
  Power (IORegisterForSystemPower)
  SMCService (IOKit AppleSMC)

        AppleSMC.kext → firmware
```

Nguyên tắc smctl §2: GUI = client; **mọi policy trong daemon**.

---

## D. Folder

```text
ThermalControl/
├── PLAN_BUILD.md
├── PLAN.md TINH_NANG.md UIUX.md ERD.md
├── README.md HUONG_DAN_BUILD.md
├── project.yml
├── Shared/{Constants, Models/*, XPC/ThermalHelperProtocol.swift}
├── App/
│   ├── ThermalControlApp.swift
│   ├── Models/HelperConnectionState.swift
│   ├── Services/{XPCClient, SensorReader, HelperInstallService}
│   ├── ViewModels/ThermalViewModel.swift
│   └── Views/{MenuBarView, DashboardView, Components/*}
├── Helper/
│   ├── main.swift XPCListener.swift SMCService.swift
│   ├── FanController.swift BatteryController.swift SafetyWatchdog.swift
│   ├── PowerObserver.swift
│   ├── Info.plist ThermalControlHelper.entitlements
│   └── com.thermalcontrol.helper.plist
└── Scripts/{install_helper.sh, uninstall_helper.sh}
```

Bundle: `com.thermalcontrol.app` / `com.thermalcontrol.helper`  
Mach = helper id. Sandbox false. `LSUIElement` true. macOS 14+.

---

## E. Thuật toán bắt buộc (copy hành vi OSS)

### E1. SMC packet (macos-smc-fan / smctl)

- `IOServiceMatching("AppleSMC")`, method `2`
- Command: info=9, read=5, write=6
- Key 4 byte ASCII thứ tự `F,0,A,c`
- `flt` = Float32 **LE** trên arm64
- `ui16/ui32/si*` = **LE** trên arm64, BE trên Intel
- Mọi write trên **một** `DispatchQueue` (Stats helper `smcQueue`)
- Write xong đọc lại; firmware apply chậm → settle 200–500ms rồi verify (smctl)

### E2. Fan unlock (Stats + macos-smc-fan + smctl)

```text
probe modeKey = F{n}Md if exists else F{n}md
probe ftst = keyExists("Ftst")

enterManual(n):
  if write(modeKey, 1) OK → return
  if !ftst → fail "unsupported"
  write(Ftst, 1); retainCount++
  sleep 3.0
  retry write(modeKey, 1) every 0.1s until 10s
  if fail → fail
  write(F{n}Tg, clamp(rpm, Mn, Mx))

leaveManual(n):
  write(modeKey, 0)
  retainCount--
  if retainCount==0 && ftst && read(Ftst)==1 → write(Ftst, 0)
```

Quiet = target Mn. Max = target Mx. System = leave all + Ftst 0.

Sau sleep: PowerObserver gọi `fan.apply()` (macfan: firmware clear Ftst).

### E3. Battery (OpenDente + smctl + AlDente)

```text
family =
  CHTE or CHIE ? tahoe
  : CH0B or CH0C ? legacy
  : none

inhibit(on):
  if forceDischarge && on==false: don't write enable while CHIE cut
  legacy: try CH0B/CH0C = 0x02 (AlDente), fallback 0x01
  tahoe: CHTE inhibit value theo probe (0/1), verify B0AC
  charging truth = B0AC > 20mA   // không tin pmset

maintain tick 2s (OpenDente cadence):
  % >= upper → inhibit
  % <= lower → allow
  else keep

forceDischarge:
  CH0I or CHIE = 1
  re-assert mỗi tick (smctl: firmware tự mở lại)
```

Uninstall/SIGTERM: allow charge + discharge off + fans system (smctl “never leave a brick”).

### E4. Safety (smctl)

- Đọc temp mỗi 1–2s. Trần 100°C; cap 105; `Tp*` cho 110.
- Mất hết temp sensor khi đang manual = unsafe → restore fan.
- Heartbeat app 5s; timeout 45s → restore **quạt only** (TINH_NANG).
- Guard nhiệt không có setting tắt.

### E5. XPC auth (smctl, không theo macos-smc-fan)

```text
shouldAccept:
  SecCodeCopyGuestWithAttributes(pid)
  Team ID == helper Team ID
  bundle allowlist com.thermalcontrol.app
  không Int32(gid) checked
  fail → invalidate, return false, NSLog, không trap
```

Client: `NSXPCConnection(machServiceName:options:[])`. AlDente dùng `.privileged` khi helper SMJobBless — ta dùng mach LaunchDaemon thì không bắt buộc privileged.

### E6. Cài helper

**Đường A — SMAppService** (OpenDente / HelperToolApp):

```swift
SMAppService.daemon(plistName: "com.thermalcontrol.helper.plist") // có đuôi
try register()
if status == .requiresApproval → open Login Items
```

Plist:

```xml
Label, BundleProgram=Contents/MacOS/ThermalControlHelper
MachServices com.thermalcontrol.helper
AssociatedBundleIdentifiers com.thermalcontrol.app
RunAtLoad, KeepAlive
```

Copy helper vào `App.app/Contents/MacOS/` lúc build.

**Đường B — script root** (smctl `daemon install`, Stats uninstall layout):

- `/Library/PrivilegedHelperTools/ThermalControlHelper`
- `/Library/LaunchDaemons/com.thermalcontrol.helper.plist` + `ProgramArguments`
- `launchctl bootstrap system`
- uninstall: restore hardware **trước** bootout

UI: nút Cài helper gọi A; README dạy B khi A fail (Personal Team).

---

## F. MVVM + UI (không đổi so UIUX)

View **cấm** IOKit/XPC/SMAppService.

`HelperConnectionState`: disconnected | connecting | connected | needsApproval | error | restoring  
+ ẩn fanless / desktop.

ViewModel contract + microcopy: giữ nguyên `PLAN.md` mục 4 và `UIUX.md` mục 7.

Poll UI 3s. Slider draft không bị poll đè.

---

## G. Phase code (một sprint, đúng thứ tự)

### P0 — Skeleton (nửa ngày)
XcodeGen 2 target, entitlements, Info.plist, Constants, copy 4 md.

DoD: `xcodegen generate &&` mở được project.

### P1 — Shared DTO + protocol
NSSecureCoding. Ping, capabilities, fan get/set, battery get/limit/charge/discharge, restore.

### P2 — SMCService
Packet + LE + serial queue + verify. Log status hex.

DoD: helper CLI debug `sudo ThermalControlHelper --probe` in FNum + keys (thêm flag debug trong main).

### P3 — Probe capabilities
Như E2/E3. Capabilities DTO.

### P4 — FanController
State machine E2 + refcount Ftst. Modes UI.

### P5 — BatteryController
E3 + tick 2s. Không ghi CHTE enable khi CHIE on.

### P6 — PowerObserver + Watchdog
`IORegisterForSystemPower` wake → apply. Thermal smctl. Heartbeat 45s.

### P7 — XPCListener + main + atexit restore
Auth E5. SIGTERM restore brick-safe.

### P8 — App services
XPCClient transport. SensorReader pin IOKit. HelperInstallService A+deep link.

### P9 — ThermalViewModel
State UIUX. Optimistic mode. lastError tiếng Việt.

### P10 — Views
360pt panel + dashboard. Ẩn khối. Copy đóng băng.

### P11 — Scripts + HUONG_DAN_BUILD + README
install restore-on-uninstall.

Không làm curve, chart, EN, Intel, setuid.

---

## H. Checklist máy thật (TINH_NANG §9 + OSS)

1. App mở, icon menu bar, không helper không crash
2. `sudo install_helper.sh` → `launchctl print system/com.thermalcontrol.helper`
3. Chấm xanh, RPM hoặc %
4. Quiet giảm RPM (có quạt)
5. System + `Ftst` đọc 0 nếu key có
6. MacBook 70–80: gần upper thì `B0AC` ~0 (không tin pmset)
7. Force discharge: % giảm khi cắm; tắt thì adapter lại
8. Sleep/wake 30s: manual còn hiệu lực (re-apply)
9. Quit app 45–60s: quạt System
10. `sudo uninstall_helper.sh`: sạc + quạt hệ thống
11. Fanless / mini: ẩn đúng khối
12. Process lạ gọi XPC: helper không chết

---

## I. Lệnh Build App dán

```text
Build a NEW macOS app ThermalControl from PLAN_BUILD.md.

Follow proven OSS behavior, do not copy GPL source:
- smctl: policy-in-daemon, XPC + Team ID auth, verify writes, LE ints,
  restore on exit, IORegisterForSystemPower, thermal guard 100/105/110,
  never write charge-enable while adapter-cut is active,
  Ftst refcount, no setuid.
- macos-smc-fan / Stats / MacFanControl: direct mode write first,
  Ftst+3s+retry on 0x82, probe F{n}Md and F{n}md, M5 has no Ftst.
- OpenDente: menu bar + helper + XcodeGen; IOKit battery read in app;
  probe CH0B/CH0C vs CHTE/CHIE.
- HelperToolApp: SMAppService.daemon(plistName with .plist).
Also ship Scripts/install_helper.sh like smctl daemon install.

Product scope: TINH_NANG.md
UI: UIUX.md frozen Vietnamese copy, Views bind ThermalViewModel only
Domain: ERD.md

Phases P0–P11 in PLAN_BUILD.md.
After P11 list files and Mac build commands.
```

---

## J. Repo clone để đọc trước khi code (không vendor)

```bash
git clone --depth 1 https://github.com/leaperone/smctl
# đọc docs/design.md docs/research-macos-smc-fan.md docs/research-battery.md

git clone --depth 1 https://github.com/agoodkind/macos-smc-fan
# đọc docs/research.md README architecture

git clone --depth 1 https://github.com/killerk3emstar/OpenDente
# đọc layout + helper protocol only; GPL — không copy file
```
