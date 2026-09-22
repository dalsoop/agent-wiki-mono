import Foundation
import AppScanKit

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let item = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    process.waitUntilExit()
    item.cancel()
}

/// Flags installed mono apps that still carry quarantine xattr (Gatekeeper / “damaged” risk).
public struct QuarantineDoctorProvider: DoctorProvider {
    public let id = "quarantine"
    private let bundleNames: [String]
    private let xattrPresent: @Sendable (String) -> Bool

    public init(
        bundleNames: [String] = [],
        xattrPresent: @escaping @Sendable (String) -> Bool = { path in
            // xattr -p com.apple.quarantine returns 0 when present.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p.arguments = ["-p", "com.apple.quarantine", path]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do {
                try p.run()
                let item = DispatchWorkItem { p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: item)
                p.waitUntilExit()
                item.cancel()
                return p.terminationStatus == 0
            } catch {
                return false
            }
        }
    ) {
        self.bundleNames = bundleNames
        self.xattrPresent = xattrPresent
    }

    public func run() async -> [DoctorFinding] {
        var names = bundleNames
        if names.isEmpty {
            // Discover from /Applications net.ranode via directory listing — best effort.
            let root = "/Applications"
            let apps = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            names = apps.filter { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
        }

        var out: [DoctorFinding] = []
        for name in names {
            guard let path = AppScan.installedBundlePath(bundleName: name) else { continue }
            if xattrPresent(path) {
                out.append(DoctorFinding(
                    category: .quarantine,
                    severity: .warn,
                    body: .init(
                        subject: name,
                        title: "\(name) is quarantined",
                        detail: path,
                        remedy: "xattr -dr com.apple.quarantine \(path)  or re-sign via ADM"
                    ),
                    source: id,
                    payload: ["path": path]
                ))
            }
        }
        if out.isEmpty {
            out.append(DoctorFinding(
                category: .quarantine,
                severity: .ok,
                body: .init(
                    subject: "fleet",
                    title: "No quarantined install copies found",
                    detail: "Checked \(names.count) bundle names"
                ),
                source: id
            ))
        }
        return out
    }
}
