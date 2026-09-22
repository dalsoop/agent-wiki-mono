import Foundation
import StateMirrorKit

/// 모든 앱 플러그인(Interop Adapter)의 기본 규약.
/// 프로세스 내에서 Interop 계약을 호출하기 위한 선택 어댑터입니다.
public protocol AppPlugin: Sendable {
    /// 고유 식별자 (앱 slug, 예: "app-build-manager", "agent-quality-coordinator")
    var id: String { get }
    
    /// 사람이 읽을 수 있는 표시 이름
    var name: String { get }
    
    /// 시맨틱 버전 문자열
    var version: String { get }
    
    /// 이 어댑터가 실행할 수 있는 명령(Action) 이름 목록
    var actions: [String] { get }
    
    /// 이 어댑터가 사전에 필요로 하는 의존 플러그인 ID 목록 (예: ["agent-vault"])
    var dependencies: [String] { get }
    
    /// 플러그인 실행 엔트리포인트 (순정 CLI argv 기반)
    func execute(action: String, argv: [String]) async throws -> [String: Sendable]
    
    /// 채널 1: StateMirror 정본 경로 직독 (프로세스 스폰 0회)
    func readFastState(context: PluginExecutionContext) -> [String: Sendable]?
}

public extension AppPlugin {
    var dependencies: [String] { [] }
    
    /// 채널 1 기본 구현: StateMirrorKit 정본 경로(~/.swift-app-state/<id>.json) 직독
    func readFastState(context: PluginExecutionContext = .current) -> [String: Sendable]? {
        let mirrorPath = StateMirror.path(app: id)
        guard FileManager.default.fileExists(atPath: mirrorPath),
              let data = FileManager.default.contents(atPath: mirrorPath) else {
            return nil
        }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Sendable]
        } catch {
            return nil
        }
    }
}

/// 플러그인 실행 중 발생할 수 있는 에러 정의
public enum PluginError: LocalizedError, Sendable, Equatable {
    case pluginNotFound(String)
    case missingDependencies(String)
    case cycleDetected([String])
    case actionNotFound(action: String, pluginId: String)
    case executionFailed(pluginId: String, reason: String)
    case invalidPayload(String)
    
    public var errorDescription: String? {
        switch self {
        case .pluginNotFound(let id):
            return "플러그인을 찾을 수 없습니다: \(id)"
        case .missingDependencies(let reason):
            return "필수 의존성 누락: \(reason)"
        case .cycleDetected(let cycle):
            return "순환 의존성이 감지되었습니다: \(cycle.joined(separator: " -> "))"
        case .actionNotFound(let action, let pluginId):
            return "플러그인 '\(pluginId)'에서 지원하지 않는 액션입니다: \(action)"
        case .executionFailed(let pluginId, let reason):
            return "플러그인 '\(pluginId)' 실행 실패: \(reason)"
        case .invalidPayload(let reason):
            return "유효하지 않은 데이터입니다: \(reason)"
        }
    }
}
