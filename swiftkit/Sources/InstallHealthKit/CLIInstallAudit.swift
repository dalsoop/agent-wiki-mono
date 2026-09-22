import Foundation

/// PATH 에 깔린 CLI 한 개의 판정 대상 값. 존재·심링크·`otool -L` 은 IO 층이 채운다.
public struct CLIInstallSpec: Equatable, Sendable {
    public let name: String
    public let path: String
    public let isSymbolicLink: Bool
    /// 심링크일 때 타겟이 존재하는가. 심링크가 아니면 `nil`.
    public let destinationExists: Bool?
    /// `otool -L` 원문. 못 읽었거나 dangling 이면 빈 문자열.
    public let otoolL: String

    public init(
        name: String,
        path: String,
        isSymbolicLink: Bool,
        destinationExists: Bool? = nil,
        otoolL: String = ""
    ) {
        self.name = name
        self.path = path
        self.isSymbolicLink = isSymbolicLink
        self.destinationExists = destinationExists
        self.otoolL = otoolL
    }
}

/// PATH CLI 설치 형태·Sparkle 링크 판정. `app-health-guard check` 가 소비한다.
public struct CLIInstallAudit: Sendable {
    public init() {}

    public func audit(_ specs: [CLIInstallSpec]) -> [HealthIssue] {
        specs
            .flatMap(auditOne)
            .sorted { lhs, rhs in
                if lhs.subject == rhs.subject { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.subject < rhs.subject
            }
    }

    public func auditOne(_ spec: CLIInstallSpec) -> [HealthIssue] {
        auditSymlink(spec) + auditSparkleRpath(spec)
    }

    /// `/opt/homebrew/bin/<cli>` 가 있으면 심링크여야 한다. 복사본은 경고, dangling 은 오류.
    public func auditSymlink(_ spec: CLIInstallSpec) -> [HealthIssue] {
        if spec.isSymbolicLink {
            if spec.destinationExists == false {
                return [HealthIssue(
                    kind: .cliSymlinkCheck,
                    severity: .error,
                    subject: spec.name,
                    detail: "dangling 심링크",
                    remedy: "\(spec.path) 타겟을 고치거나 PATH CLI 를 재설치한다."
                )]
            }
            return []
        }
        return [HealthIssue(
            kind: .cliSymlinkCheck,
            severity: .warning,
            subject: spec.name,
            detail: "CLI가 복사본입니다 — 심링크로 전환하세요",
            remedy: "복사본을 지우고 \(spec.path) 를 번들 Helpers 바이너리로 심링크한다."
        )]
    }

    /// `otool -L` 에 Sparkle 이 보이면 CLI 가 업데이터를 끌고 있는 것이다 — GUI 가 담당해야 한다.
    public func auditSparkleRpath(_ spec: CLIInstallSpec) -> [HealthIssue] {
        guard spec.otoolL.contains("Sparkle") else { return [] }
        return [HealthIssue(
            kind: .cliSparkleRpath,
            severity: .warning,
            subject: spec.name,
            detail: "CLI 바이너리가 Sparkle 을 로드한다 — 업데이트는 GUI 앱이 담당하므로 CLI 에는 불필요하다.",
            remedy: "CLI 타깃에서 Sparkle/SparkleUpdateKit 링크를 제거하고 재설치한다."
        )]
    }
}
