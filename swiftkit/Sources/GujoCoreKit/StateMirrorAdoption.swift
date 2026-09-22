import Foundation
import StateMirrorKit

/// 상태 미러 게시 지점 — 함대 계약 채택 도구(app-fleet-quality-auditor adopt)가 생성한 골격.
///
/// 계약(CLAUDE.md "앱 상태 미러"): GUI 앱은 핵심 모델 요약을
/// `~/.swift-app-state/<앱>.json` 으로 게시해 에이전트가 스크린샷 없이 상태를 읽는다.
/// 도구는 앱 의미를 지어내지 않는다 — 최소 필드(status/generatedAt)만 게시하고,
/// 앱 고유 요약 필드와 호출 지점 연결은 앱 소유자가 채운다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/gujo.json`.
    public static let appName = "gujo"

    public struct State: Codable, Sendable {
        public var status: String
        public var generatedAt: Date
        /// 로컬에 설치된 Gujo 제품 수.
        public var installedProductCount: Int
        /// 렌더 캐시(products/)에 남은 제품 디렉터리 수.
        public var cachedProductCount: Int
        /// 마지막 프루닝에서 정리한 제품 캐시 수.
        public var lastPrunedProductCount: Int

        public init(
            status: String,
            installedProductCount: Int = 0,
            cachedProductCount: Int = 0,
            lastPrunedProductCount: Int = 0,
            generatedAt: Date = Date()
        ) {
            self.status = status
            self.installedProductCount = installedProductCount
            self.cachedProductCount = cachedProductCount
            self.lastPrunedProductCount = lastPrunedProductCount
            self.generatedAt = generatedAt
        }
    }

    /// 모델 상태가 바뀌는 지점(로드 완료·작업 종료 등)에서 호출한다.
    public static func publish(
        status: String = "ok",
        installedProductCount: Int = 0,
        cachedProductCount: Int = 0,
        lastPrunedProductCount: Int = 0
    ) {
        StateMirror.publish(
            app: appName,
            State(
                status: status,
                installedProductCount: installedProductCount,
                cachedProductCount: cachedProductCount,
                lastPrunedProductCount: lastPrunedProductCount)
        )
    }
}
