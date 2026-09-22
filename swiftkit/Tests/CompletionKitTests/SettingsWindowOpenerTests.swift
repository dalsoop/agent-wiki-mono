import XCTest
@testable import CompletionKit

/// URL 스킴 충돌 회귀 방지.
///
/// 개발 빌드(.dev)와 설치본이 **둘 다** 같은 스킴을 claim 하면 NSWorkspace 가 스킴만 보고 앱을
/// 골라 엉뚱한 쪽이 뜬다(실측: 개발 번들에서 연 URL 이 /Applications 설치본을 실행). 빌드
/// 스크립트가 개발 빌드 스킴에 `-dev` 를 붙여 분리하므로, 앱 코드는 스킴을 절대 하드코딩하면
/// 안 되고 Info.plist 에서 읽어야 한다.
@MainActor
final class SettingsWindowOpenerTests: XCTestCase {

    private func bundle(scheme: String?) -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swotest-\(UUID().uuidString).bundle", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        var info: [String: Any] = ["CFBundleIdentifier": "test.bundle"]
        if let scheme {
            info["CFBundleURLTypes"] = [["CFBundleURLName": "T", "CFBundleURLSchemes": [scheme]]]
        }
        (info as NSDictionary).write(to: dir.appendingPathComponent("Info.plist"), atomically: true)
        return Bundle(url: dir)!
    }

    func testReadsCanonicalScheme() {
        XCTAssertEqual(SettingsWindowOpener.registeredScheme(in: bundle(scheme: "keyboardtyper")),
                       "keyboardtyper")
    }

    /// 핵심 — 개발 빌드의 분리된 스킴도 그대로 읽어야 한다. 하드코딩이면 여기서 깨진다.
    func testReadsDevSuffixedScheme() {
        XCTAssertEqual(SettingsWindowOpener.registeredScheme(in: bundle(scheme: "keyboardcodingtyper-dev")),
                       "keyboardcodingtyper-dev")
    }

    func testNoURLTypesReturnsNil() {
        XCTAssertNil(SettingsWindowOpener.registeredScheme(in: bundle(scheme: nil)))
    }
}
