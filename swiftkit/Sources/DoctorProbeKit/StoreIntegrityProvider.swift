import Foundation

/// Flags app data stores that can no longer be read, and rescued copies left
/// behind when one was.
///
/// Most mono apps keep their state as JSON under
/// `~/Library/Application Support/<App>/`. A store that fails to parse looks
/// exactly like an empty one to the app that owns it — and the next save can
/// overwrite whatever the user had (observed in rightclick: a corrupt
/// `actions.json` became an empty list, then one edit destroyed the original).
/// The owning app is the right place to *protect* the data; this provider is how
/// the fleet gets to *see* that it happened.
///
/// Two findings:
/// - `.fail` — a store file exists but does not parse. The owning app is running
///   on an empty list right now.
/// - `.warn` — rescued copies (`*.corrupt-*.json`) are present. Data was saved
///   from destruction, but nobody has looked at it yet.
public struct StoreIntegrityDoctorProvider: DoctorProvider {
    public let id = "store-integrity"

    /// Marker used by apps that quarantine an unreadable store before rewriting.
    public static let rescuedMarker = ".corrupt-"

    /// 검사 대상 앱 디렉터리 이름. 비면 전부 — 하지만 기본 사용처(fleet-doctor)는
    /// 우리 앱 목록을 넘긴다. 남의 앱까지 훑으면 우리가 고칠 수 없는 소음이 쌓인다
    /// (실측: UnityHub 의 스칼라 JSON 4건이 실패로 잡혔다).
    private let appNames: Set<String>
    private let root: URL
    private let listDirectory: @Sendable (URL) -> [String]
    private let readFile: @Sendable (URL) -> Data?
    private let now: @Sendable () -> Date

    public init(
        appNames: [String] = [],
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        listDirectory: @escaping @Sendable (URL) -> [String] = { url in
            (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        },
        readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.appNames = Set(appNames)
        self.root = root
        self.listDirectory = listDirectory
        self.readFile = readFile
        self.now = now
    }

    public func run() async -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        for appDir in listDirectory(root).sorted() {
            if !appNames.isEmpty, !appNames.contains(appDir) { continue }
            let dir = root.appendingPathComponent(appDir, isDirectory: true)
            let entries = listDirectory(dir)
            let jsonFiles = entries.filter { $0.hasSuffix(".json") }
            guard !jsonFiles.isEmpty else { continue }

            let rescued = jsonFiles.filter { $0.contains(Self.rescuedMarker) }
            if !rescued.isEmpty {
                findings.append(DoctorFinding(
                    id: "store-integrity.rescued.\(appDir)",
                    category: .other,
                    severity: .warn,
                    body: .init(
                        subject: appDir,
                        title: "복구된 스토어 사본이 남아 있음",
                        detail: "\(rescued.count)개: \(rescued.sorted().joined(separator: ", "))",
                        remedy: "\(dir.path) 에서 내용을 확인하고, 되살릴 게 없으면 지우세요."
                    ),
                    source: id,
                    observedAt: now(),
                    payload: ["dir": dir.path, "count": String(rescued.count)]
                ))
            }

            // 격리본은 이미 깨진 채로 보관된 것이라 파싱 검사 대상이 아니다.
            for file in jsonFiles.filter({ !$0.contains(Self.rescuedMarker) }).sorted() {
                let url = dir.appendingPathComponent(file)
                guard let data = readFile(url) else {
                    findings.append(unreadable(appDir: appDir, url: url, why: "읽을 수 없음"))
                    continue
                }
                if ProbeJSON.raw(from: data, options: [.allowFragments]) == nil {
                    findings.append(unreadable(appDir: appDir, url: url, why: "JSON 파싱 실패"))
                }
            }
        }
        return findings
    }

    private func unreadable(appDir: String, url: URL, why: String) -> DoctorFinding {
        DoctorFinding(
            id: "store-integrity.unreadable.\(appDir).\(url.lastPathComponent)",
            category: .other,
            severity: .fail,
            body: .init(
                subject: appDir,
                title: "앱 데이터 스토어가 깨졌음",
                detail: "\(url.lastPathComponent) — \(why). 앱은 지금 빈 목록으로 동작하고 있을 수 있습니다.",
                remedy: "쓰기 전에 원본을 옆으로 치우는지 확인하세요(덮어쓰면 복구 불가). 백업이 있으면 되돌리세요."
            ),
            source: id,
            payload: ["path": url.path]
        )
    }
}
