# Nghiệm thu ThermalControl 1.3

Máy mục tiêu: MacBookPro18,4 arm64, macOS 15.7.2. Chỉ kết quả bản cuối mới tính nghiệm thu; build nguồn không thay thế bản cài. Không suy rộng mọi Mac.

## Baseline

- Nguồn trước thay đổi: `.build/FullValidation/baseline-{status.txt,sha256.txt}` và `baseline.patch`.
- Lần trước: 55 app-hosted +15 helper-hostless =70 tests PASS; Release PASS (`.build/button-hit-area-{tests,release}.log`).
- Button coordinate test cũng PASS khi bỏ shape +/-: chưa tái hiện lỗi chỉ click chữ trên app cài. Không tuyên bố root cause đã xác minh.
- App/helper PID555/308 chỉ quan sát lịch sử; không xác nhận đang chạy bản mới.

## Checklist control

Mỗi nhóm cần: action đúng một lần khi click label/padding/mép trong; ngoài bounds/disabled không chạy; keyboard/focus/accessibility; pending, lỗi, retry và thành công đúng phạm vi. EN/VI, light/dark, Reduce Motion và cửa sổ nhỏ.

| Màn | Controls/luồng | Trạng thái |
|---|---|---|
| Tổng quan | Auto/Êm/Max, Sạc đầy/Giới hạn; không editor chi tiết | NOT RUN |
| Quạt | Mode, từng RPM, +/-/slider/field, Apply/Cancel, bounds/partial readback | NOT RUN |
| Pin | Full/Limit, upper/lower gap5, Apply/Cancel, start-confirm/Stop xả, target/deadline | NOT RUN |
| Nhiệt | available/stale/empty, không biến lỗi thành0 | NOT RUN |
| Cài đặt | locale, login denied/rollback, helper grant/install/update/reconnect/cancel | NOT RUN |
| Menu | quick modes, gear đúngSettings, Quit safe, nochart/manualeditor | NOT RUN |
| Toàn cục | Reload, Reset confirm/partial/retry, close≠Quit, keyboardQuit | NOT RUN |

## Ma trận xác minh

| Nhóm | Điều kiện | Test/log | Trạng thái |
|---|---|---|---|
| Trust | wrong/missing/invalid identity reject; signed correctpeer accepted | ClientAuthenticatorTests + signed integration | NOT RUN |
| Capability | CHTE/legacy/CHIEonly/none; unsupported rejected helper | BatteryControllerTests/HelperXPCServiceTests | NOT RUN |
| Safety | thermal hold/stale, missing1sample, monotonic deadlines, off verified | SafetyLifecycleTests/BatteryControllerTests | NOT RUN |
| Discharge | maintainconfirmed+AC+percent>upper; stop target/60min/unplug/stale/sleep/Quit/failure | fake clock + hardware safe-stop | NOT RUN |
| Draft/readback | edit no write; Apply/Cancel; persistconfirmed; stale reply/cancel/reconnect | Fan/BatteryViewModelTests | NOT RUN |
| Restore/Quit | percomponenterrors/retry; transientonlyQuit; keepopenonfailure | HelperXPCServiceTests/ThermalViewModelTests | NOT RUN |
| State | missing/corrupt/schema/saveerror; retaincharge restart, no transientreplay | StateStore/PersistedState tests | NOT RUN |
| Hit-testing | padding/corners/outside/disabled + installed repro | ButtonHitAreaTests + real UI | NOT RUN |
| Telemetry/session | no staleasnew, no duplicate timers, hidden chart samplingoff | session/reader tests + runtime | NOT RUN |
| Build | Debug+Release+analyze, warning classification | .build/FullValidation | NOT RUN |
| Package | finalsignature matching, missinghelperfails, safeRestoreBeforeDelete | shell syntax + signed package/install | NOT RUN |
| Performance | CPU/memory/wakeups/XPC/SMC/latency baseline/post3×10min | sameconditions Release | NOT RUN |
| Hardware | 5sleepwake, 3helperrestart, soak30min, actual stop/restore | separateconsent | BLOCKED — chưa cấp phép |
| Bản cài | fingerprint/version/signature/path/PID đúng bản đã test | separate installconsent | BLOCKED — chưa cấp phép |

## Kết quả code/test hiện tại — 2026-10-25

- **111 tests PASS**:77 app-hosted +34 helper-hostless,0failures. Log `.build/FullValidation/verified-tests.log`, gồm finite RPM, draft/readback, native coordinate, missing telemetry, Quit lock/partial retry, battery deadline/stop, monotonic thermal, identity âm tính và session visibility.
- **Release BUILD SUCCEEDED**, **Debug ANALYZE SUCCEEDED**: `verified-release.log`, `verified-analyze.log`. Debug compile/build được thực hiện trong test action; chưa có signed install/auth integration PASS.
- `bash -n`4scripts, EN/VI `plutil -lint`, `git diff --check`:PASS. Shell syntax không chứng minh installer chạy đúng trên hệ thống thật.
- AppIntents metadata warning do target không dùng AppIntents, không compiler error. Service-status error22 trong test trước do truy vấn SMAppService của app-host; đã tách test status khỏi service thật, log cuối không còn error22. Save-failure log do ca fault-injection chủ động dùng path không ghi được; có assertion failure được nhận, không lỗi ghi state production. Security test có thể log DetachedSignatures DB thiếu khi verify binary giả; negative tests vẫn pass, không coi là bằng chứng positive peer auth.
- Kết quả ma trận: phần fake/native-hosted tự động của capability/safety/discharge/draft/Quit/state/hit-testing/session PASS theo log. **UI app cài, VoiceOver/keyboard thật, signed peer positive, package/install, benchmark,5sleepwake/3restart/30minsoak vẫn NOT RUN/BLOCKED**. Bảng trên giữ trạng thái đầu-cuối chưa nghiệm thu, không đổi thành PASS chỉ từ unit tests.
- Đã tạo `.build/packages/1.3.0/ThermalControl-1.3.0.pkg` và `.dmg`, package script exit0; app/helper payload được Apple Development ký và native verify cùng Team. Log `package.log`, checksum `artifact-sha256.txt`. PKG container **chưa ký** (`pkgutil --check-signature`: no signature), chưa notarize; không coi là public release hay đã cài PASS. Không đụng thêm tracked dist.
- App Info phiên bản1.3.0/build5, helper1.3.0/protocol3. Package Release compile lại thành công sau cập nhật Info.plist;111tests là source logic bản trước đổi metadata này.
- Không thay `/Applications` hoặc helper đang chạy; PID555app/308helper được quan sát lại trước bàn giao, vẫn bản cũ. Update protocol2 sang3 bị chặn có chủ ý, cần migration an toàn được duyệt riêng; không tự ghi đè.

## Migration và ramp — cập nhật 2026-10-25

Các trạng thái ở mục baseline phía trên là lịch sử, không phải tình trạng hiện tại.
- User cho phép migration/native update, thử fan/charge theo tầng; chưa cho forcedischarge hoặc sleepcycles.
- Backup đầy đủ `.build/migration-20261025-091729`; update ramp backup `.build/pre-ramp-20261025-142658`. Không xóa backup. Legacy restore giữ numeric55/50 nhưng maintain=false/charging=true; bridge regression đã bổ sung, không ép upper100 như protocol3.
- Native unregister2/register3 thành công và đã dừng PID308; helper1.3/protocol3 rồi update1.4/protocol4 bằng native release/unregister/register. Không rawbootout cưỡng bức. App đã thay vào /Applications, helper mới thật sự chạy; identity/signature payload verified.
- Charge55/50 khôi phục qua XPC+readback+state.json, fanAuto, dischargeOff/registerverified; logs `restored-status.log` và `diagnostic-after-failure-status.log`.
- Ramp250RPM/s/tick250ms code đã có,132testsPASS checkpoint; diagnostic mới133testsPASS(87app46helper), ReleasebuildPASS. Log `fan-diagnostic-tests.log`/`fan-diagnostic-release.log`.
- **Hardware ramp FAIL, chưa nghiệm thu:** `fan-ramp-hardware-repro.log` ghi expectedF0Tg2295.56689453125, immediateactual2317.0 flt4; restoremode0 immediateactual1. Status sau đó mode0 cả2fan, noerror. Điều này cho thấy immediate readback không đủ; đang sửa bounded asynchronous exactack, không nới tolerance/giấu lỗi.
- Ảnh thật `installed-dashboard.png`/`ramp-ui-initial.png` đã xem: cảnh báo readback hiện hữu, không coi screenshot thành UI PASS. Chưa benchmark/VoiceOver/sleep/forcedischarge; còn legacy /Library/LaunchDaemons artifact đã backup nhưng chưa cleanup để tránh dualregistration sau reboot (cần kiểm tra và quyềnroot phù hợp).

## Readback chờ xác nhận — bản chưa triển khai

- Đã sửa target-write thành pending exact acknowledgement ở tick sau, tối đa1giây; không ghi bước tiếp hoặc watchdog reassert khi pending. Endpoint chỉ complete sau ack. Auto ghi mode0 rồi kiểm tra50ms tối đa250ms, không sửa protectedFTST.
- **136testsPASS** (87app49helper): `fan-async-final-tests.log`; ReleasePASS `fan-async-final-release.log`. Signed bản chờ tại `.build/FanRamp/Thermal Control Async.app`.
- Chưa hardwarePASS: lần tái hiện thực `--test-fan-ramp` trên bản diagnostic cũ vẫn exit1. Không coi test fake trễ là chứng minh firmware sẽ nhận trong1giây.
- Lệnh native unregister để cập nhật bản Async bị permission classifier từ chối; chưa thực thi. Phải xin xác nhận rõ cho lần stop/update helper này, không dùng đường khác bypass. Helper đang giữAuto/55–50/dischargeOff theo status cuối; kiểm lại PID/state khi được duyệt.

## Async update đã được duyệt và thực hiện

- User xác nhận rõ lần stop/update Async và thử Max khoảng3giây rồi Auto. Native unregister cũ thành công, verify service biến mất, thay signed app, native register lại; charge55/50 readback xác nhận.
- **136testsPASS**, Release/analysisPASS; bản Async đã cài vào /Applications, helper1.4.0/protocol4 PID37333 tại lần kiểm tra.
- `fan-ramp-hardware-async.log`: Start bị từ chối `Verify fail F0Ac`, trước ramp vì SMC trả actual0/target0 cả2fan trongAuto. `async-final-safe-status.log` xác nhận mode0 cả2fan, min1200, maintain55/50, dischargefalse/registerverified, nohelpererror. Không vượt guard bằng targetdưới min hoặc ép khởi động fan đang dừng.
- **Hardware ramp vẫn BLOCKED/FAIL chưa nghiệm thu**, không xác nhận readback trễ đã hết trên quạt đang quay. Cần thử lại khi fan tự quay với baseline hợp lệ; không gây tải/quá nhiệt để ép điều kiện. Fan stop0 trongAuto có thể hợp lệ firmware, không đủ bằng chứng kết luận phần cứng hỏng.

## Gate an toàn

- Không chạy helper/SMC writes/install/sudo chỉ để test UI; dùng fake actions.
- Không ép quá nhiệt; thermal/deadline60phút test fake clock. Hardware case chỉ PASS khi thực sự chạy.
- Không chạy old `--probe`/`--selftest` dưới giả định read-only.
- Signed install không có identity phù hợp hoặc legacy protocol không tương thích: BLOCKED, không fallback ad-hoc hoặc overwrite mù.
- PASS / FAIL / BLOCKED / NOT RUN phải kèm bằng chứng; còn NOT RUN không gọi “test hết”.
