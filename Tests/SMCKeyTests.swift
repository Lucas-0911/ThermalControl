import XCTest
@testable import ThermalControl

/// Guards the SMCKey refactor: every rawValue must stay byte-identical to the
/// literal it replaced, because those four-char codes are reverse-engineered
/// AppleSMC names — a typo silently returns garbage instead of failing.
final class SMCKeyTests: XCTestCase {
    // MARK: - Fan factory keys

    func testFanKeysBuildTheRightFourCharCodes() {
        XCTAssertEqual(SMCKey.fanCount.rawValue, "FNum")
        XCTAssertEqual(SMCKey.fanActual(0).rawValue, "F0Ac")
        XCTAssertEqual(SMCKey.fanTarget(2).rawValue, "F2Tg")
        XCTAssertEqual(SMCKey.fanMin(1).rawValue, "F1Mn")
        XCTAssertEqual(SMCKey.fanMax(3).rawValue, "F3Mx")
        XCTAssertEqual(SMCKey.fanMode(0).rawValue, "F0Md")
        XCTAssertEqual(SMCKey.fanModeLower(0).rawValue, "F0md")
    }

    func testFTSTKeys() {
        XCTAssertEqual(SMCKey.ftst.rawValue, "FTST")
        XCTAssertEqual(SMCKey.ftstLower.rawValue, "Ftst")
    }

    // MARK: - Battery keys

    func testBatteryKeys() {
        XCTAssertEqual(SMCKey.b0AC.rawValue, "B0AC")
        XCTAssertEqual(SMCKey.b0AV.rawValue, "B0AV")
        XCTAssertEqual(SMCKey.ch0B.rawValue, "CH0B")
        XCTAssertEqual(SMCKey.ch0C.rawValue, "CH0C")
        XCTAssertEqual(SMCKey.ch0I.rawValue, "CH0I")
        XCTAssertEqual(SMCKey.chTE.rawValue, "CHTE")
        XCTAssertEqual(SMCKey.chIE.rawValue, "CHIE")
    }

    // MARK: - Temperature vocabulary

    /// Every rawValue must match the exact literal previously hardcoded in
    /// `Constants.tempKeys` (and later centralized here).
    func testTempKeysMatchHistoricalLiterals() {
        let expected: [(SMCKey, String)] = [
            (.tp01, "Tp01"), (.tp05, "Tp05"), (.tp09, "Tp09"), (.tp0D, "Tp0D"),
            (.tp0H, "Tp0H"), (.tp0L, "Tp0L"), (.tp0T, "Tp0T"), (.tp0b, "Tp0b"),
            (.tp0f, "Tp0f"), (.tc0P, "TC0P"),
            (.tg05, "Tg05"), (.tg0D, "Tg0D"), (.tg0L, "Tg0L"), (.tg0T, "Tg0T"),
            (.tg0b, "Tg0b"), (.tg0f, "Tg0f"), (.tg0P, "Tg0P"), (.tg1F, "Tg1F"),
            (.te05, "Te05"), (.te0F, "Te0F"), (.te0P, "Te0P"),
            (.ts0P, "Ts0P"), (.ts0G, "Ts0G"),
        ]
        for (key, raw) in expected {
            XCTAssertEqual(key.rawValue, raw, "SMCKey rawValue drifted from the historical literal")
        }
    }

    /// Sanity: canonical temp set has no dupes and matches TC.tempKeys exactly.
    func testTempKeysSet() {
        let raws = SMCKey.tempKeys.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "tempKeys contains duplicates")
        XCTAssertEqual(raws, TC.tempKeys, "TC.tempKeys must mirror SMCKey.tempKeys")
    }

    func testThermalTripKeysAreSubsetOfTempKeys() {
        let all = Set(SMCKey.tempKeys.map(\.rawValue))
        for key in SMCKey.thermalTripKeys {
            XCTAssertTrue(all.contains(key.rawValue), "\(key.rawValue) not in tempKeys")
        }
        // Protect the exact watchdog trip set.
        XCTAssertEqual(SMCKey.thermalTripKeys.map(\.rawValue),
                       ["Tp01", "Tp05", "Tp09", "Tp0D", "TC0P", "Te05", "Ts0P"])
    }

    // MARK: - FourCharCode

    func testFourCharCodeEncoding() {
        XCTAssertEqual(SMCKey("Tp01").fourCC, 0x5470_3031)
        XCTAssertEqual(SMCKey("ABC").fourCC, 0x4142_4320) // padded to 4
    }
}