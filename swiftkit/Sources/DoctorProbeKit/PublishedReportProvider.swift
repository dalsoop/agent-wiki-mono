import Foundation
import StateMirrorKit
import StateRootKit

/// Collects app-published doctor reports from StateMirror and ~/.swift-app-doctor.
public struct PublishedDoctorProvider: DoctorProvider {
    public let id = "app-published"
    private let doctorDir: String
    private let stateDir: String

    public init(
        doctorDir: String = StateRootKit.path(".swift-app-doctor"),
        stateDir: String = StateMirror.dir
    ) {
        self.doctorDir = doctorDir
        self.stateDir = stateDir
    }

    public func run() async -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        let fm = FileManager.default

        for dir in [doctorDir, stateDir] {
            let files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for name in files where name.hasSuffix(".json") {
                let path = (dir as NSString).appendingPathComponent(name)
                guard let data = fm.contents(atPath: path),
                      let report = Self.decodeReport(data) else { continue }
                guard !report.findings.isEmpty || dir == doctorDir else { continue }
                if report.findings.isEmpty { continue }
                for f in report.findings {
                    var copy = f
                    if copy.source.isEmpty { copy.source = id }
                    out.append(copy)
                }
            }
        }

        if out.isEmpty {
            out.append(DoctorFinding(
                category: .published,
                severity: .info,
                body: .init(
                    subject: "fleet",
                    title: "No app-published doctor reports yet",
                    detail: "Apps can write ~/.swift-app-doctor/<app>.json or StateMirror doctor findings",
                    remedy: "Adopt DoctorKit.AppDoctorReport in individual apps over time"
                ),
                source: id
            ))
        }
        return out
    }

    public static func decodeReport(_ data: Data) -> AppDoctorReport? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(AppDoctorReport.self, from: data)
        } catch {}

        struct Env: Decodable {
            let app: String?
            let state: FlexibleState?
        }
        struct FlexibleState: Decodable {
            let findings: [DoctorFinding]?
            let doctor: AppDoctorReport?
        }
        do {
            let env = try dec.decode(Env.self, from: data)
            if let d = env.state?.doctor { return d }
            if let f = env.state?.findings, let app = env.app {
                return AppDoctorReport(app: app, findings: f)
            }
        } catch {}
        return nil
    }
}
