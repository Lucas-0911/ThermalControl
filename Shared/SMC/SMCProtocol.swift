import Foundation

/// Test seam over the AppleSMC driver.
///
/// `SMCService` conforms without change — the concrete shared instance is
/// still constructed exactly where it was; this only lets `FanController`,
/// `BatteryController`, `SafetyWatchdog` and `SensorReader` accept mocks in
/// future unit tests.
///
/// Note: the conformance must stay a no-op. In particular `SMCService` is
/// deliberately NOT an actor: it is shared between the fan controller (locked),
/// battery controller (locked) and the app's local reader, and actorizing it
/// would force `async` into the timing-sensitive SMC write paths.
protocol SMCProtocol: AnyObject {
    func open() throws
    func close()
    func keyExists(_ key: String) -> Bool
    func info(_ key: String) throws -> SMCKeyInfo
    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8])
    func readUInt8(_ key: String) throws -> UInt8
    func readDouble(_ key: String) throws -> Double
    func readCelsius(_ key: String) -> Double?
    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool) throws
    func writeDouble(_ key: String, _ value: Double, verify: Bool) throws
    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws
    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws
}

extension SMCService: SMCProtocol {}

// NOTE: `FanControlling` / `BatteryControlling` protocol seams are declared in
// Helper/ControllerSeams.swift — they reference only Shared types here, but
// the concrete controllers exist only in the Helper target.