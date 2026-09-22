import XCTest
@testable import InstallerKit

final class InstallerChecksumTests: XCTestCase {
    func testSha256HexMatchesKnownVectors() {
        XCTAssertEqual(URLSessionReleaseAssetDownloader.sha256Hex(of: Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(URLSessionReleaseAssetDownloader.sha256Hex(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testParseExpectedHashHandlesCoreutilsFormat() {
        let sums = """
        ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  mai
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 *bootstrap
        """
        XCTAssertEqual(URLSessionReleaseAssetDownloader.parseExpectedHash(from: sums, asset: "mai"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(URLSessionReleaseAssetDownloader.parseExpectedHash(from: sums, asset: "bootstrap"),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertNil(URLSessionReleaseAssetDownloader.parseExpectedHash(from: sums, asset: "not-listed"))
    }

    func testVerifyChecksumFailsClosedWhenNoSumsPublished() async throws {
        let failure = await URLSessionReleaseAssetDownloader.verifyChecksum(
            asset: "mai", file: URL(fileURLWithPath: "/nonexistent"), sumsURL: nil, timeoutSeconds: 1)
        // 닫혔다는 사실만으론 부족하다 — 왜 닫혔는지가 설치 로그의 유일한 단서다.
        let reason = try XCTUnwrap(failure, "missing SHA256SUMS must fail closed")
        XCTAssertTrue(reason.contains("SHA256SUMS"), reason)
    }
}
