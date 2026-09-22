import Foundation

/// `/Applications/<name>.app` 이 이름 목록마다 있어야 한다.
public struct InstalledApplicationBundleProvider: DoctorProvider {
    public let id: String
    private let appNames: [String]
    private let applicationsDirectory: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        id: String,
        appNames: [String],
        applicationsDirectory: String = "/Applications",
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.id = id
        self.appNames = appNames
        self.applicationsDirectory = applicationsDirectory
        self.fileExists = fileExists
    }

    public func run() async -> [DoctorFinding] {
        appNames.compactMap { name in
            let path = (applicationsDirectory as NSString).appendingPathComponent("\(name).app")
            guard !fileExists(path) else { return nil }
            return DoctorFinding(
                category: .install,
                severity: .fail,
                body: .init(
                    subject: name,
                    title: "스테이지 앱 번들이 없다",
                    detail: path,
                    remedy: "해당 앱을 설치하거나 stageApps 목록을 실제 번들 이름과 맞춘다"
                ),
                source: id
            )
        }
    }
}
