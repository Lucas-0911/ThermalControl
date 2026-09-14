import Foundation
import IOKit

enum SMCType {
    case ui8, ui16, ui32, si8, si16, si32, flt, fpe2, other
    init(_ fourCC: String) {
        switch fourCC.trimmingCharacters(in: .whitespaces) {
        case "ui8": self = .ui8
        case "ui16": self = .ui16
        case "ui32": self = .ui32
        case "si8": self = .si8
        case "si16": self = .si16
        case "si32": self = .si32
        case "flt": self = .flt
        case "fpe2": self = .fpe2
        default: self = .other
        }
    }
}

struct SMCKeyInfo {
    let key: String
    let type: SMCType
    let dataSize: UInt32
    let typeFourCC: String
}

/// DOC: these description strings double as the UI contract. Errors are built
/// in the ROOT HELPER process and shipped to the app over XPC as a `String?`
/// (`lastError`), so they are not re-localizable at display time.
/// Changing them alters what users see — treat as frozen until a future XPC
/// protocol bump replaces the `String?` channel with a typed error code.
enum SMCError: Error, CustomStringConvertible {
    case notFound, open(kern_return_t), call(kern_return_t), badLayout
    case missing(String), status(UInt8), type(String), verify(String)
    var description: String {
        switch self {
        case .notFound: return "AppleSMC không tìm thấy"
        case .open(let r): return "IOServiceOpen \(r)"
        case .call(let r): return "IOConnectCall \(r)"
        case .badLayout: return "SMCKeyData stride != 80"
        case .missing(let k): return "Không có key \(k)"
        case .status(let s): return String(format: "SMC 0x%02x", s)
        case .type(let k): return "Sai kiểu \(k)"
        case .verify(let k): return "Verify fail \(k)"
        }
    }
}

/// AppleSMC userspace — same 80-byte SMCKeyData_t layout as Stats / SMCKit.
final class SMCService {
    private let queue = DispatchQueue(label: "com.thermalcontrol.smc")
    private var connection: io_connect_t = 0
    private let method: UInt32 = 2
    private let cmdRead: UInt8 = 5
    private let cmdWrite: UInt8 = 6
    private let cmdInfo: UInt8 = 9
    private let stOK: UInt8 = 0
    private let stMissing: UInt8 = 0x84

    func open() throws { try queue.sync { try openUnlocked() } }

    func close() {
        queue.sync {
            if connection != 0 { IOServiceClose(connection); connection = 0 }
        }
    }

    func keyExists(_ key: String) -> Bool { (try? info(key)) != nil }

    func info(_ key: String) throws -> SMCKeyInfo {
        try queue.sync { try infoUnlocked(key) }
    }

    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) {
        try queue.sync {
            let meta = try infoUnlocked(key)
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = FourCharCode.from(key)
            input.keyInfo.dataSize = meta.dataSize
            input.data8 = cmdRead
            try call(&input, &output)
            if output.result == stMissing { throw SMCError.missing(key) }
            if output.result != stOK { throw SMCError.status(output.result) }
            return (meta, output.byteArray(count: Int(meta.dataSize)))
        }
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        let (_, b) = try readBytes(key)
        guard let v = b.first else { throw SMCError.type(key) }
        return v
    }

    func readDouble(_ key: String) throws -> Double {
        let (meta, bytes) = try readBytes(key)
        return try decode(meta, bytes)
    }

    func readCelsius(_ key: String) -> Double? {
        guard let (meta, bytes) = try? readBytes(key), !bytes.isEmpty else { return nil }
        if let v = try? decode(meta, bytes), v > 1, v < 150 { return v }
        if bytes.count >= 4 {
            let f = Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
            if f > 1, f < 150 { return f }
        }
        if bytes.count >= 2 {
            let sp = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
            if sp > 1, sp < 150 { return sp }
        }
        return nil
    }

    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool = false) throws {
        try writeBytes(key, [value], verify: verify)
    }

    func writeDouble(_ key: String, _ value: Double, verify: Bool = false) throws {
        let meta = try info(key)
        try writeBytes(key, encode(meta, value), verify: verify)
    }

    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws {
        try queue.sync {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = FourCharCode.from(key)
            input.data8 = cmdWrite
            input.keyInfo.dataSize = size
            input.setBytes(bytes)
            try call(&input, &output)
            if output.result != stOK { throw SMCError.status(output.result) }
        }
    }

    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws {
        try queue.sync {
            let meta = try infoUnlocked(key)
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.key = FourCharCode.from(key)
            input.data8 = cmdWrite
            input.keyInfo.dataSize = meta.dataSize
            input.setBytes(bytes)
            try call(&input, &output)
            if output.result != stOK { throw SMCError.status(output.result) }
        }
        if verify {
            Thread.sleep(forTimeInterval: TC.writeSettle)
            let (_, back) = try readBytes(key)
            let n = min(bytes.count, back.count)
            if Array(bytes.prefix(n)) != Array(back.prefix(n)) {
                throw SMCError.verify(key)
            }
        }
    }

    private func infoUnlocked(_ key: String) throws -> SMCKeyInfo {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCharCode.from(key)
        input.data8 = cmdInfo
        try call(&input, &output)
        if output.result == stMissing { throw SMCError.missing(key) }
        if output.result != stOK { throw SMCError.status(output.result) }
        let type = output.keyInfo.dataType.toFourCC()
        return SMCKeyInfo(
            key: key,
            type: SMCType(type),
            dataSize: output.keyInfo.dataSize,
            typeFourCC: type
        )
    }

    private func openUnlocked() throws {
        guard connection == 0 else { return }
        guard MemoryLayout<SMCKeyData>.stride == 80 else { throw SMCError.badLayout }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.notFound }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        // Stats / smcFanControl use type 0. Type 1 opens but keys do not resolve.
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError.open(kr) }
        connection = conn
    }

    private func call(_ input: inout SMCKeyData, _ output: inout SMCKeyData) throws {
        if connection == 0 { try openUnlocked() }
        let inSize = MemoryLayout<SMCKeyData>.stride
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(connection, method, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS else { throw SMCError.call(kr) }
    }

    private var little: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private func decode(_ meta: SMCKeyInfo, _ b: [UInt8]) throws -> Double {
        switch meta.type {
        case .flt:
            var x = b
            while x.count < 4 { x.append(0) }
            return Double(x.withUnsafeBytes { $0.load(as: Float.self) })
        case .fpe2:
            guard b.count >= 2 else { return 0 }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
        case .ui8: return Double(b.first ?? 0)
        case .si8: return Double(Int8(bitPattern: b.first ?? 0))
        case .ui16: return Double(loadU16(b))
        case .si16: return Double(Int16(bitPattern: loadU16(b)))
        case .ui32: return Double(loadU32(b))
        case .si32: return Double(Int32(bitPattern: loadU32(b)))
        case .other: throw SMCError.type(meta.key)
        }
    }

    private func encode(_ meta: SMCKeyInfo, _ value: Double) throws -> [UInt8] {
        switch meta.type {
        case .flt:
            var f = Float(value)
            return withUnsafeBytes(of: &f) { Array($0) }
        case .fpe2:
            let raw = UInt16((max(0, value) * 4).rounded())
            return [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case .ui8:
            return [UInt8(clamping: Int(value.rounded()))]
        default:
            throw SMCError.type(meta.key)
        }
    }

    private func loadU16(_ b: [UInt8]) -> UInt16 {
        guard b.count >= 2 else { return 0 }
        return little ? UInt16(b[0]) | UInt16(b[1]) << 8 : UInt16(b[0]) << 8 | UInt16(b[1])
    }

    private func loadU32(_ b: [UInt8]) -> UInt32 {
        guard b.count >= 4 else { return 0 }
        if little {
            return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }
}

private struct SMCKeyData {
    struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Vers()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    func byteArray(count: Int) -> [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0.prefix(max(0, count))) }
    }

    mutating func setBytes(_ list: [UInt8]) {
        withUnsafeMutableBytes(of: &bytes) { buf in
            for (i, v) in list.enumerated() where i < buf.count {
                buf[i] = v
            }
        }
    }
}

private extension FourCharCode {
    static func from(_ str: String) -> FourCharCode {
        var s = str
        while s.utf8.count < 4 { s.append(" ") }
        return s.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    func toFourCC() -> String {
        let b = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(bytes: b, encoding: .ascii) ?? "????"
    }
}
