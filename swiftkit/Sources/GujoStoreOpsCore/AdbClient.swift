import InteropKit
import Foundation

#if os(macOS)
import CommandKit
import LocalizationKit

/// 로컬 adb 래퍼 — Mac only.
public struct AdbClient: Sendable {
    private let runner: any CommandRunning
    private let adbPath: String

    public init(runner: any CommandRunning = ProcessCommandRunner(), adbPath: String? = nil) {
        self.runner = runner
        if let adbPath {
            self.adbPath = adbPath
        } else {
            let candidates = [
                HostPlatform.cliBinPath("adb"),
                StoreOpsPaths.usrLocalCLI("adb"),
            ] + StoreOpsPaths.androidSDKAdb
            self.adbPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "adb"
        }
    }

    public var resolvedPath: String { adbPath }

    public func isAvailable() async -> Bool {
        let r = await runner.run(adbPath, ["version"], timeout: 5)
        return r.exitCode == 0
    }

    public func devices() async -> [OpsDevice] {
        let r = await runner.run(adbPath, ["devices", "-l"], timeout: 8)
        guard r.exitCode == 0 else { return [] }
        return Self.parseDevices(r.stdout)
    }

    /// 기기 실측 — 목록 `device` 만 믿지 않는다.
    ///
    /// `adb shell`/`exec-out` 은 Foundation.Process + 파이프에서 타임아웃(exit 15) 나는
    /// 환경이 있어(실측: shell hang, get-state 18ms OK), **get-state** 를 1차 프로브로 쓴다.
    /// install 가능 여부와 동일 계열(state=device).
    public func shellAlive(serial: String) async -> (ok: Bool, detail: String) {
        let r = await runner.run(
            adbPath,
            ["-s", serial, "get-state"],
            timeout: 6
        )
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.exitCode == 0, out == "device" {
            return (true, "get-state=device")
        }
        let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        if !out.isEmpty {
            detail = "get-state=\(out) exit \(r.exitCode)"
        } else if !err.isEmpty {
            detail = String(err.prefix(120))
        } else {
            detail = "exit \(r.exitCode)"
        }
        return (false, detail)
    }

    /// 실측 진단: binary · version · devices -l · 기기별 shell.
    public func diagnose() async -> AdbDiagnosis {
        var checks: [AdbCheck] = []
        let pathOK = FileManager.default.isExecutableFile(atPath: adbPath) || adbPath == "adb"
        checks.append(AdbCheck(
            id: "binary",
            title: CLILocalization.string("AdbClient.title"),
            ok: pathOK || adbPath == "adb",
            detail: adbPath
        ))

        let ver = await runner.run(adbPath, ["version"], timeout: 5)
        let available = ver.exitCode == 0
        let versionLine = ver.stdout.split(whereSeparator: \.isNewline).first.map(String.init)
        checks.append(AdbCheck(
            id: "version",
            title: "adb version",
            ok: available,
            detail: available ? (versionLine ?? "ok") : (ver.stderr.isEmpty ? "exit \(ver.exitCode)" : ver.stderr)
        ))
        guard available else {
            return AdbDiagnosis.classify(
                adbAvailable: false,
                adbPath: adbPath,
                devices: [],
                checks: checks
            )
        }

        let devRun = await runner.run(adbPath, ["devices", "-l"], timeout: 8)
        let raw = devRun.stdout
        checks.append(AdbCheck(
            id: "devices_cmd",
            title: "adb devices -l",
            ok: devRun.exitCode == 0,
            detail: devRun.exitCode == 0
                ? "exit 0 · \(raw.split(whereSeparator: \.isNewline).count) lines"
                : "exit \(devRun.exitCode) \(devRun.stderr.prefix(80))"
        ))
        let list = devRun.exitCode == 0 ? Self.parseDevices(raw) : []
        checks.append(AdbCheck(
            id: "devices_parse",
            title: CLILocalization.string("AdbClient.title-2"),
            ok: true,
            detail: list.isEmpty ? "0 devices" : "\(list.count) devices · listedReady \(list.filter(\.isReady).count)"
        ))

        var shellOK = Set<String>()
        for d in list where d.isReady {
            let serial = d.serial ?? d.id
            let probe = await shellAlive(serial: serial)
            checks.append(AdbCheck(
                id: "probe.\(serial)",
                title: "get-state \(serial)",
                ok: probe.ok,
                detail: "\(d.isEmulator ? "emu" : "phys") · \(probe.detail)"
            ))
            if probe.ok { shellOK.insert(serial) }
        }
        if list.contains(where: \.isReady) {
            checks.append(AdbCheck(
                id: "usable_any",
                title: CLILocalization.string("AdbClient.title-3"),
                ok: !shellOK.isEmpty,
                detail: shellOK.isEmpty
                    ? "listed device 있으나 get-state≠device"
                    : "\(shellOK.count) serial usable"
            ))
        }
        let phys = shellOK.filter { !AdbDiagnosis.isEmulatorSerial($0) }
        checks.append(AdbCheck(
            id: "physical",
            title: CLILocalization.string("AdbClient.title-4"),
            ok: !phys.isEmpty || shellOK.isEmpty, // N/A when no shell at all — not fail if only missing phys
            detail: phys.isEmpty
                ? (shellOK.isEmpty ? CLILocalization.string("AdbClient.string-3") : CLILocalization.format("AdbClient.string-2", "\(shellOK.count)"))
                : "\(phys.count) physical"
        ))
        // physical check: if only emu, mark ok=false to surface in UI (user wanted real phone)
        if let idx = checks.firstIndex(where: { $0.id == "physical" }), !shellOK.isEmpty, phys.isEmpty {
            checks[idx] = AdbCheck(
                id: "physical",
                title: CLILocalization.string("AdbClient.title-4"),
                ok: false,
                detail: CLILocalization.string("AdbClient.detail")
            )
        }

        return AdbDiagnosis.classify(
            adbAvailable: true,
            adbPath: adbPath,
            devices: list,
            shellOkSerials: shellOK,
            checks: checks,
            adbVersion: versionLine,
            rawDevicesOutput: raw
        )
    }

    public func install(apkPath: String, serial: String? = nil) async throws {
        var args = ["install", "-r", apkPath]
        if let serial { args = ["-s", serial, "install", "-r", apkPath] }
        let r = await runner.run(adbPath, args, timeout: 180)
        guard r.exitCode == 0 else {
            throw StoreOpsError.network(r.stderr.isEmpty ? r.stdout : r.stderr)
        }
    }

    public static func parseDevices(_ stdout: String) -> [OpsDevice] {
        stdout.split(whereSeparator: \.isNewline).compactMap { line -> OpsDevice? in
            let s = String(line)
            if s.hasPrefix("List of devices") || s.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { return nil }
            let serial = parts[0]
            let rawState = parts[1]
            // device → ready (서버·UI 공통). unauthorized/offline 은 원문 유지.
            let state = rawState == "device" ? "ready" : rawState
            var model: String?
            for p in parts.dropFirst(2) {
                if p.hasPrefix("model:") {
                    model = String(p.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
                }
            }
            let label: String
            if let model {
                label = "\(model) (\(serial))"
            } else if state == "unauthorized" {
                label = CLILocalization.format("AdbClient.string", "\(serial)")
            } else if state == "offline" {
                label = "offline · \(serial)"
            } else {
                label = serial
            }
            return OpsDevice(
                id: serial,
                label: label,
                platform: "android",
                serial: serial,
                state: state
            )
        }
    }
}
#endif
