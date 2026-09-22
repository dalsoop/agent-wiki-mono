import Foundation

/// 설치돼 있으면 로드돼 있어야 한다. 미설치는 통과한다.
public struct LaunchAgentLoadedIfInstalledProvider: DoctorProvider {
    public let id: String
    private let label: String
    private let inspect: @Sendable () -> (installed: Bool, loaded: Bool)

    public init(
        id: String,
        label: String,
        inspect: @escaping @Sendable () -> (installed: Bool, loaded: Bool)
    ) {
        self.id = id
        self.label = label
        self.inspect = inspect
    }

    public func run() async -> [DoctorFinding] {
        let status = inspect()
        guard status.installed else { return [] }
        guard status.loaded else {
            return [DoctorFinding(
                category: .runtime,
                severity: .fail,
                body: .init(
                    subject: label,
                    title: "LaunchAgent가 설치돼 있는데 로드되지 않았다",
                    detail: label,
                    remedy: "launchctl bootstrap/enable 로 해당 label 을 로드한다"
                ),
                source: id
            )]
        }
        return []
    }
}
