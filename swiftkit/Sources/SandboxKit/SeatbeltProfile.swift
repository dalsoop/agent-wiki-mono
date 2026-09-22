import Foundation
import StateRootKit

/// macOS Seatbelt (`sandbox-exec`) 프로필 동적 생성기.
///
/// 커널 레벨에서 샌드박스 외부 파일시스템 쓰기를 차단하고,
/// 지정된 룸 스크래치패드와 임시 디렉터리에만 쓰기를 허용하는 Scheme 정책을 생성한다.
public struct SeatbeltProfile: Sendable, Equatable {
    public let sandboxPath: String
    public let tmpPath: String
    public let allowedWritePaths: [String]
    public let allowNetwork: Bool
    /// 설정되면 outbound 는 이 localhost 포트만 연다(allowlist 프록시).
    public let proxyPort: UInt16?

    public init(
        sandboxPath: String,
        tmpPath: String = NSTemporaryDirectory(),
        allowedWritePaths: [String] = [],
        allowNetwork: Bool = true,
        proxyPort: UInt16? = nil
    ) {
        self.sandboxPath = (sandboxPath as NSString).standardizingPath
        self.tmpPath = (tmpPath as NSString).standardizingPath
        self.allowedWritePaths = allowedWritePaths.map { ($0 as NSString).standardizingPath }
        self.allowNetwork = allowNetwork
        self.proxyPort = proxyPort
    }

    /// Seatbelt Scheme 프로필 문자열을 생성한다.
    public func generateScheme() -> String {
        var lines: [String] = [
            ";; Pure One-Way Room Sandbox Seatbelt Profile (v1)",
            "(version 1)",
            "(allow default)",
        ]

        if let port = proxyPort {
            lines.append("(deny network-outbound)")
            lines.append("(allow network-outbound (remote ip \"localhost:\(port)\"))")
            lines.append("(allow network-outbound (remote ip \"*:\(port)\"))")
        } else if !allowNetwork {
            lines.append("(deny network*)")
        }

        // 전체 홈 디렉터리 및 루트 디렉터리에 대한 쓰기 금지
        let home = StateRootKit.resolveHost(environment: [:])
        lines.append(";; 1. 홈 디렉터리 기본 쓰기 차단")
        lines.append("(deny file-write* (subpath \"\(escapePath(home))\"))")

        // 2. 허용된 샌드박스 영역에만 명시적 쓰기 허용
        lines.append(";; 2. 룸 스크래치패드 및 임시 디렉터리만 쓰기 허용")
        lines.append("(allow file-write* (subpath \"\(escapePath(sandboxPath))\"))")
        lines.append("(allow file-write* (subpath \"\(escapePath(tmpPath))\"))")
        lines.append("(allow file-write* (literal \"/dev/null\"))")
        lines.append("(allow file-write* (literal \"/dev/zero\"))")
        lines.append("(allow file-write* (literal \"/dev/dtracehelper\"))")
        lines.append("(allow file-write* (literal \"/dev/tty\"))")
        lines.append("(allow file-write* (subpath \"/private/tmp\"))")
        lines.append("(allow file-write* (subpath \"/private/var/folders\"))")

        // 3. 추가 허용 쓰기 경로가 있으면 등록 (예: 작업 worktree 등)
        for extra in allowedWritePaths {
            lines.append("(allow file-write* (subpath \"\(escapePath(extra))\"))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func escapePath(_ path: String) -> String {
        // 개행문자(\n, \r)는 LISP 문법을 깨뜨리므로 제거
        let noNewlines = path.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return noNewlines
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
