import Foundation

/// 방의 프로세스 격리 백엔드.
///
/// - `seatbelt`: macOS sandbox-exec 기반. 기본값이며, 기존 JSON 에 키가 없으면 이 값으로 디코딩된다.
/// - `srt`: Anthropic sandbox-runtime (srt) 기반. `srt --settings <json> <command>` 로 감싼다.
public enum SandboxBackend: String, Codable, Sendable, Equatable, CaseIterable {
    case seatbelt
    case srt
}
