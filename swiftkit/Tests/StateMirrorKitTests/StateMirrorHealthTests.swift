import Testing
@testable import StateMirrorKit

/// 함대 표준 건강 필드 파생 계약 — 앱마다 제각각이면 "모든 앱 감시"가 무의미해진다.
@Suite struct StateMirrorHealthTests {
    @Test func statusNil은ok() {
        #expect(StateMirrorHealth.status(lastError: nil) == "ok")
    }

    @Test func status빈문자열은ok_센티넬금지() {
        // 계약: nil 이면 키 생략 — 빈 문자열이 "error" 로 해석되면 센티넬이 된다.
        #expect(StateMirrorHealth.status(lastError: "") == "ok")
    }

    @Test func status원문있으면error() {
        #expect(StateMirrorHealth.status(lastError: "Keychain -25293") == "error")
    }

    @Test func lastError키상수() {
        // untyped 게시와 typed Codable 이 같은 키를 써야 소비자가 하나의 경로로 읽는다.
        #expect(StateMirrorHealth.lastErrorKey == "lastError")
    }
}
