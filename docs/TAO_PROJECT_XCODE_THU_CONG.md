# Tạo project Xcode bằng tay (không dùng XcodeGen)

1. Xcode → File → New → Project → macOS → App
2. Product Name: `Thermal Control`
3. Interface: SwiftUI, Language: Swift
4. Bundle ID: `com.thermalcontrol.app`
5. Bỏ Sandbox (Signing & Capabilities → xóa App Sandbox nếu có)

6. File → New → Target → macOS → Command Line Tool  
   Product Name: `ThermalControlHelper`  
   Bundle ID: `com.thermalcontrol.helper`

7. Xóa file mẫu Xcode tạo. Kéo toàn bộ thư mục `App/`, `Shared/` vào target Thermal Control.  
   Kéo `Helper/*.swift` + `Shared/` vào target ThermalControlHelper.

8. Target Thermal Control:
   - Info.plist = `App/Info.plist`
   - Entitlements = `App/ThermalControl.entitlements`
   - Disable sandbox

9. Target Helper:
   - Info.plist = `Helper/Info.plist`
   - Entitlements = `Helper/ThermalControlHelper.entitlements`

10. Build helper trước, rồi app. Cài helper bằng `Scripts/install_helper.sh`.
