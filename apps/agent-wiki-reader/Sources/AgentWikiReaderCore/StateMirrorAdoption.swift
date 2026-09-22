import Foundation
import StateMirrorKit

/// 상태 미러 게시 지점 — 스캐폴드가 앱 생성 시점에 심는 함대 계약(CLAUDE.md "앱 상태 미러").
///
/// GUI 앱은 핵심 모델 요약을 `~/.swift-app-state/agent-wiki-reader.json` 으로 게시해
/// 에이전트·스크립트가 스크린샷 없이 `swift-app-router state agent-wiki-reader` 로 읽는다.
/// 스캐폴드는 앱 의미를 지어내지 않는다 — 최소 필드(status/generatedAt)만 게시하고,
/// 앱 고유 요약 필드와 호출 지점 연결은 앱 소유자가 채운다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/agent-wiki-reader.json`.
    public static let appName = "agent-wiki-reader"

    public struct State: Codable, Sendable {
        public var status: String
        public var generatedAt: Date
        public var surface: String

        public init(status: String, generatedAt: Date = Date(), surface: String = "reader") {
            self.status = status
            self.generatedAt = generatedAt
            self.surface = surface
        }
    }

    /// 모델 상태가 바뀌는 지점(로드 완료·작업 종료 등)에서 호출한다.
    public static func publish(_ state: State) {
        StateMirror.publish(app: appName, state)
    }

    public static func publish(status: String = "ok") {
        StateMirror.publish(app: appName, State(status: status))
    }
}
