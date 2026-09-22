import XCTest
@testable import VaultwardenKit

final class TOTPTests: XCTestCase {
    // RFC 6238 SHA-1 test vector: secret "12345678901234567890" (base32 GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ)
    func testRFC6238SHA1Vectors() {
        let cfg = TOTPGenerator.parse("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")!
        var c8 = cfg; c8.digits = 8
        XCTAssertEqual(TOTPGenerator.code(c8, at: Date(timeIntervalSince1970: 59)), "94287082")
        XCTAssertEqual(TOTPGenerator.code(c8, at: Date(timeIntervalSince1970: 1111111109)), "07081804")
        XCTAssertEqual(TOTPGenerator.code(c8, at: Date(timeIntervalSince1970: 20000000000)), "65353130")
    }

    func testOtpauthURIParsing() {
        let cfg = TOTPGenerator.parse("otpauth://totp/Example:user@x.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=7&period=60&algorithm=SHA256")
        XCTAssertEqual(cfg?.digits, 7)
        XCTAssertEqual(cfg?.period, 60)
        XCTAssertEqual(cfg?.algorithm, .sha256)
    }

    func testInvalidSeed() {
        XCTAssertNil(TOTPGenerator.parse("not base32 !!!"))
    }

    func testSecondsRemainingRange() {
        let cfg = TOTPGenerator.parse("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")!
        let r = TOTPGenerator.secondsRemaining(cfg)
        XCTAssertTrue((1...30).contains(r))
    }
}
