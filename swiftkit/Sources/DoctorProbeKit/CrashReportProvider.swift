import Foundation

/// Surfaces recent crash reports under DiagnosticReports for fleet bundle prefixes.
///
/// **같은 앱의 반복 크래시를 하나로 묶는다** — `.ips` 파일 하나당 1 finding 을 내면
/// launch-크래시 루프(예: app-health-guard 가 8/9 에 20회 SIGABRT)가 doctor 를 통째로
/// 잠근다. 앱명(`app-health-guard-YYYY-MM-DD-HHMMSS.ips` → `app-health-guard`)으로
/// 그룹화해 count · 최신 시각 · 최신 파일을 하나의 finding 에 담는다(2026-08-10).
public struct CrashReportDoctorProvider: DoctorProvider {
    public let id = "crash-reports"
    private let reportsDir: String
    private let prefixes: [String]
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private let listFiles: @Sendable (String) -> [String]
    private let fileMtime: @Sendable (String) -> Date?

    public init(
        reportsDir: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Logs/DiagnosticReports"),
        prefixes: [String] = ["net.ranode", "App", "Mounter", "Agent"],
        maxAge: TimeInterval = 60 * 60 * 24 * 14,
        now: @escaping @Sendable () -> Date = { Date() },
        listFiles: @escaping @Sendable (String) -> [String] = { dir in
            (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        },
        fileMtime: @escaping @Sendable (String) -> Date? = { path in
            (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
    ) {
        self.reportsDir = reportsDir
        self.prefixes = prefixes
        self.maxAge = maxAge
        self.now = now
        self.listFiles = listFiles
        self.fileMtime = fileMtime
    }

    public func run() async -> [DoctorFinding] {
        let names = listFiles(reportsDir)
        let cutoff = now().addingTimeInterval(-maxAge)

        // 앱명별 그룹화 — 같은 앱의 반복 크래시를 하나로.
        var groups: [String: CrashGroup] = [:]
        for name in names {
            guard name.hasSuffix(".ips") || name.hasSuffix(".crash") else { continue }
            let matched = prefixes.contains { name.localizedCaseInsensitiveContains($0) }
            guard matched else { continue }
            let path = (reportsDir as NSString).appendingPathComponent(name)
            let mtime = fileMtime(path) ?? .distantPast
            guard mtime >= cutoff else { continue }

            let appName = Self.appName(from: name) ?? name
            if var g = groups[appName] {
                g.count += 1
                if mtime > g.latestMtime {
                    g.latestMtime = mtime
                    g.latestPath = path
                    g.latestName = name
                }
                groups[appName] = g
            } else {
                groups[appName] = CrashGroup(
                    count: 1, latestMtime: mtime, latestPath: path, latestName: name
                )
            }
        }

        var findings: [DoctorFinding] = groups.map { appName, g in
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            let stamp = formatter.string(from: g.latestMtime)
            // 활성 크래시(최근 24시간 내)만 fail — 그 이전은 과거 일시적 기록으로 warn.
            // 계속 크래시 중인 앱은 새 .ips 가 쌓여 24시간 내 최신이 계속 갱신되므로 fail 유지,
            // 고쳐진 앱은 새 .ips 가 안 쌓이고 24시간 지나 자동 warn 으로 내려간다(2026-08-10).
            let recent = now().timeIntervalSince(g.latestMtime) < 24 * 3600
            return DoctorFinding(
                category: .crash,
                severity: recent ? .fail : .warn,
                body: .init(
                    subject: appName,
                    title: g.count > 1
                    ? "Crash: \(appName) ×\(g.count) (최신 \(stamp))\(recent ? "" : " — 과거 기록")"
                    : "Crash: \(appName) (\(stamp))\(recent ? "" : " — 과거 기록")",
                    detail: g.latestPath,
                    remedy: recent
                    ? "Open Console / reinstall app; check last ship for regression"
                    : "최근 24h 내 재발 없음 — 과거 일시적 기록. 재발하면 fail 로 올린다"
                ),
                source: id,
                observedAt: g.latestMtime,
                payload: ["path": g.latestPath, "count": "\(g.count)", "latest": g.latestName,
                          "active": recent ? "true" : "false"]
            )
        }.sorted { $0.subject < $1.subject }

        if findings.isEmpty {
            findings.append(DoctorFinding(
                category: .crash,
                severity: .ok,
                body: .init(
                    subject: "fleet",
                    title: "No recent fleet crash reports",
                    detail: "Scanned \(reportsDir) (last \(Int(maxAge / 86400))d)"
                ),
                source: id
            ))
        }
        return findings
    }

    /// 파일명에서 앱명 추출. `<app>-YYYY-MM-DD-HHMMSS.ips` → `<app>`.
    /// 날짜 패턴이 없으면 확장자를 뗀 파일명 전체(구형 .crash 등).
    /// `public static` 이라 단위테스트가 직접 친다.
    public static func appName(from filename: String) -> String? {
        let pattern = #"^(.+?)-\d{4}-\d{2}-\d{2}-\d{6}\.(ips|crash)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let r = Range(m.range(at: 1), in: filename)
        else {
            return (filename as NSString).deletingPathExtension
        }
        return String(filename[r])
    }
}

/// 같은 앱의 크래시 모음 — 그룹화 중간값.
private struct CrashGroup {
    var appName: String { (latestName as NSString).deletingPathExtension }
    var count: Int
    var latestMtime: Date
    var latestPath: String
    var latestName: String
}
