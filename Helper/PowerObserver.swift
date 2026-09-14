import Foundation
import IOKit.pwr_mgt
import os

/// `iokit_common_msg(...)` macros in IOMessage.h do not import into Swift.
private enum PowerMessage {
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
}

final class PowerObserver {
    private var root: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var port: IONotificationPortRef?
    var onWake: (() -> Void)?

    func start() {
        let ctx = Unmanaged.passUnretained(self)
        // IORegisterForSystemPower expects UnsafeMutablePointer<IONotificationPortRef?>
        // and allocates the port when the property is still optional.
        root = IORegisterForSystemPower(ctx.toOpaque(), &port, { ref, _, messageType, arg in
            guard let ref else { return }
            let me = Unmanaged<PowerObserver>.fromOpaque(ref).takeUnretainedValue()
            switch messageType {
            case PowerMessage.canSystemSleep, PowerMessage.systemWillSleep:
                if let arg {
                    IOAllowPowerChange(me.root, Int(bitPattern: arg))
                }
            case PowerMessage.systemHasPoweredOn:
                me.onWake?()
            default:
                break
            }
        }, &notifier)
        guard root != 0, let port else {
            Logger.power.error("IORegisterForSystemPower failed")
            return
        }
        if let run = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), run, .defaultMode)
        }
    }
}
