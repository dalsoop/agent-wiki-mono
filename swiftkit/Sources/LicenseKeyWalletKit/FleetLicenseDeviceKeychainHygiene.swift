import Foundation

/// fleet 전 앱 `license-device` Keychain 잔재 스캔·삭제 (앱 안 관리용).
///
/// 기기 UUID 는 ``FileLicenseDeviceStore`` 가 Application Support 파일로 보관한다.
/// 여기 있는 건 **구 per-app Keychain 항목을 함대 단위로 걷어내는** 제어면이다,
/// 앱마다 사람 입력을 요구하지 않는다 (`security -w` 금지).
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public enum FleetLicenseDeviceKeychainHygiene {
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct Report: Codable, Sendable, Equatable {
        public var legacyServices: [String]
        public var fileDeviceCount: Int
        public var fileDirectory: String
        public var purged: Int
        public var applied: Bool

        public init(
            legacyServices: [String],
            fileDeviceCount: Int,
            fileDirectory: String,
            purged: Int,
            applied: Bool
        ) {
            self.legacyServices = legacyServices
            self.fileDeviceCount = fileDeviceCount
            self.fileDirectory = fileDirectory
            self.purged = purged
            self.applied = applied
        }

        public var legacyCount: Int { legacyServices.count }
        public var healthy: Bool { legacyCount == 0 }
    }

    public static var fileDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(FileLicenseDeviceStore.directoryName, isDirectory: true)
    }

    /// dump-keychain 메타만 — 비밀값 미출력.
    public static func scanLegacyLicenseDeviceServices() -> [String] {
        let dump = runSecurity(["dump-keychain"])
        return parseLicenseDeviceServices(from: dump)
    }

    public static func fileDeviceIDCount() -> Int {
        let dir = fileDirectoryURL
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return 0
        }
        return names.filter { $0.hasSuffix(".id") }.count
    }

    /// `apply == false` 이면 스캔만. `true` 이면 account=license-device 항목 삭제 (값 읽기 없음).
    public static func run(apply: Bool) -> Report {
        let services = scanLegacyLicenseDeviceServices()
        var purged = 0
        if apply {
            for service in services {
                let code = runSecurityExit([
                    "delete-generic-password",
                    "-s", service,
                    "-a", "license-device",
                ])
                if code == 0 { purged += 1 }
            }
        }
        return Report(
            legacyServices: services.sorted(),
            fileDeviceCount: fileDeviceIDCount(),
            fileDirectory: fileDirectoryURL.path,
            purged: purged,
            applied: apply)
    }

    // MARK: - parse / process

    static func parseLicenseDeviceServices(from dump: String) -> [String] {
        var cur: [String: String] = [:]
        var found = Set<String>()
        func commit() {
            guard let acct = cur["acct"], acct == "license-device",
                  let svce = cur["svce"] else { return }
            if svce.hasPrefix("net.ranode.")
                || svce.hasPrefix("com.dalsoop.")
                || svce.hasPrefix("kr.")
            {
                found.insert(svce)
            }
        }
        for line in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("class:") {
                commit()
                cur = [:]
            }
            if let v = blob(after: "\"svce\"", in: s) { cur["svce"] = v }
            if let v = blob(after: "\"acct\"", in: s) { cur["acct"] = v }
        }
        commit()
        return Array(found)
    }

    private static func blob(after key: String, in line: String) -> String? {
        // "svce"<blob>="value"
        let marker = "\(key)<blob>=\""
        guard let r = line.range(of: marker) else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static let securityTimeout: TimeInterval = 45

    @discardableResult
    private static func runSecurity(_ args: [String]) -> String {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return ""
        }
        // 파이프를 병렬 드레인하면서 프로세스 타임아웃 (가득 찬 파이프 데드락 + hang 방지)
        let box = DrainBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.out = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let deadline = Date().addingTimeInterval(securityTimeout)
        while p.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            p.terminate()
            let killDeadline = Date().addingTimeInterval(2)
            while p.isRunning, Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        _ = group.wait(timeout: .now() + 5)
        return String(data: box.out, encoding: .utf8) ?? ""
        #else
        return ""
        #endif
    }

    private static func runSecurityExit(_ args: [String]) -> Int32 {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return 1
        }
        let deadline = Date().addingTimeInterval(securityTimeout)
        while p.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            p.terminate()
            return 124
        }
        return p.terminationStatus
        #else
        return 1
        #endif
    }

    private final class DrainBox: @unchecked Sendable {
        var out = Data()
    }
}
