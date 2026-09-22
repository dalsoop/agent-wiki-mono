import Foundation
import InteropKit

/// Checks `DependencyCatalog` needs against the local machine.
public struct DependencyDoctorProvider: DoctorProvider {
    public let id = "dependency"
    private let catalog: DependencyCatalog
    private let isExecutable: @Sendable (String) -> Bool
    private let fileExists: @Sendable (String) -> Bool
    private let env: [String: String]
    private let commonBinRoots: [String]

    public init(
        catalog: DependencyCatalog,
        isExecutable: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        },
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        env: [String: String] = ProcessInfo.processInfo.environment,
        commonBinRoots: [String] = [
            HostPlatform.homebrewBin, "/usr/local/bin", "/usr/bin", "/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
    ) {
        self.catalog = catalog
        self.isExecutable = isExecutable
        self.fileExists = fileExists
        self.env = env
        self.commonBinRoots = commonBinRoots
    }

    public func run() async -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        for app in catalog.apps where app.enabled {
            for need in app.needs {
                let ok = evaluate(need)
                if ok {
                    out.append(DoctorFinding(
                        category: .dependency,
                        severity: .ok,
                        body: .init(
                            subject: app.id,
                            title: "\(app.displayName): \(need.label)",
                            detail: "satisfied (\(need.kind.rawValue)=\(need.value))"
                        ),
                        source: id
                    ))
                } else if need.optional {
                    out.append(DoctorFinding(
                        category: .dependency,
                        severity: .info,
                        body: .init(
                            subject: app.id,
                            title: "\(app.displayName): optional \(need.label) missing",
                            detail: "\(need.kind.rawValue)=\(need.value)",
                            remedy: "Install if you need this feature"
                        ),
                        source: id
                    ))
                } else {
                    out.append(DoctorFinding(
                        category: .dependency,
                        severity: .fail,
                        body: .init(
                            subject: app.id,
                            title: "\(app.displayName): missing \(need.label)",
                            detail: "\(need.kind.rawValue)=\(need.value) not found",
                            remedy: "Install dependency or update dependencies.json"
                        ),
                        source: id
                    ))
                }
            }
        }
        return out
    }

    private func evaluate(_ need: DependencyNeed) -> Bool {
        switch need.kind {
        case .binary:
            if need.value.contains("/") {
                return isExecutable(need.value)
            }
            return commonBinRoots.contains { isExecutable(($0 as NSString).appendingPathComponent(need.value)) }
        case .path:
            return fileExists(need.value)
        case .bundle:
            // Best-effort: Application Support / Applications lookup by id string as path fragment.
            let roots = ["/Applications", "\(NSHomeDirectory())/Applications"]
            for root in roots {
                let apps = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
                for name in apps where name.hasSuffix(".app") {
                    let plist = "\(root)/\(name)/Contents/Info.plist"
                    if let data = FileManager.default.contents(atPath: plist) {
                        do {
                            if let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                               let bid = obj["CFBundleIdentifier"] as? String,
                               bid == need.value {
                                return true
                            }
                        } catch {}
                    }
                }
            }
            return false
        case .port:
            // Port open check is best-effort stub in kit (apps can inject); v1 always true if numeric.
            return Int(need.value) != nil
        case .env:
            return !(env[need.value] ?? "").isEmpty
        }
    }
}
