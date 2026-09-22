import Foundation
import LocalizationKit

/// 개별 실측 증거 — UI 에 ✓/✗ 로 보여 “장식”이 아님을 증명한다.
public struct AdbCheck: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var ok: Bool
    public var detail: String

    public init(id: String, title: String, ok: Bool, detail: String) {
        self.id = id
        self.title = title
        self.ok = ok
        self.detail = detail
    }
}

/// 로컬 adb 사용성 진단 — devices 목록만이 아니라 shell 실측·에뮬/실기기 구분.
public struct AdbDiagnosis: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case ready
        case adbMissing
        case noDevices
        case unauthorized
        case offline
        case mixedNotReady
        /// adb devices 는 device 인데 shell 이 실패 (부팅 중·권한).
        case listedButShellDead
    }

    public var kind: Kind
    public var adbAvailable: Bool
    public var adbPath: String
    public var adbVersion: String?
    public var devices: [OpsDevice]
    /// devices -l 에 device/ready 로 잡힌 수 (shell 전).
    public var listedReadyCount: Int
    /// `adb shell echo` 성공한 serial 수 — 설치 가능 판정 기준.
    public var shellOkCount: Int
    public var emulatorShellOkCount: Int
    public var physicalShellOkCount: Int
    public var unauthorizedCount: Int
    public var offlineCount: Int
    public var otherNotReadyCount: Int
    public var shellOkSerials: [String]
    public var checks: [AdbCheck]
    public var rawDevicesOutput: String?
    public var scannedAt: Date

    public init(
        kind: Kind,
        adbAvailable: Bool,
        adbPath: String,
        adbVersion: String? = nil,
        devices: [OpsDevice] = [],
        listedReadyCount: Int = 0,
        shellOkCount: Int = 0,
        emulatorShellOkCount: Int = 0,
        physicalShellOkCount: Int = 0,
        unauthorizedCount: Int = 0,
        offlineCount: Int = 0,
        otherNotReadyCount: Int = 0,
        shellOkSerials: [String] = [],
        checks: [AdbCheck] = [],
        rawDevicesOutput: String? = nil,
        scannedAt: Date = Date()
    ) {
        self.kind = kind
        self.adbAvailable = adbAvailable
        self.adbPath = adbPath
        self.adbVersion = adbVersion
        self.devices = devices
        self.listedReadyCount = listedReadyCount
        self.shellOkCount = shellOkCount
        self.emulatorShellOkCount = emulatorShellOkCount
        self.physicalShellOkCount = physicalShellOkCount
        self.unauthorizedCount = unauthorizedCount
        self.offlineCount = offlineCount
        self.otherNotReadyCount = otherNotReadyCount
        self.shellOkSerials = shellOkSerials
        self.checks = checks
        self.rawDevicesOutput = rawDevicesOutput
        self.scannedAt = scannedAt
    }

    /// 하위 호환: shell 통과 기기 수.
    public var readyCount: Int { shellOkCount }

    /// shell 실측 통과가 있어야 설치 가능.
    public var isReady: Bool { kind == .ready && shellOkCount > 0 }

    public var onlyEmulator: Bool {
        shellOkCount > 0 && physicalShellOkCount == 0 && emulatorShellOkCount > 0
    }

    public var title: String {
        switch kind {
        case .ready:
            if onlyEmulator {
                return CLILocalization.format("AdbDiagnosis.return", shellOkCount)
            }
            return CLILocalization.format("AdbDiagnosis.return-2", shellOkCount)
        case .adbMissing: return CLILocalization.string("AdbDiagnosis.return-3")
        case .noDevices: return CLILocalization.string("AdbDiagnosis.return-4")
        case .unauthorized: return CLILocalization.string("AdbDiagnosis.return-5")
        case .offline: return CLILocalization.string("AdbDiagnosis.return-6")
        case .mixedNotReady: return CLILocalization.string("AdbDiagnosis.return-7")
        case .listedButShellDead: return CLILocalization.string("AdbDiagnosis.return-8")
        }
    }

    public var summary: String {
        switch kind {
        case .ready:
            if onlyEmulator {
                return CLILocalization.string("AdbDiagnosis.return-9")
            }
            return CLILocalization.string("AdbDiagnosis.return-10")
        case .adbMissing:
            return CLILocalization.string("AdbDiagnosis.return-11")
        case .noDevices:
            return CLILocalization.string("AdbDiagnosis.return-12")
        case .unauthorized:
            return CLILocalization.string("AdbDiagnosis.return-13")
        case .offline:
            return CLILocalization.string("AdbDiagnosis.return-14")
        case .mixedNotReady:
            return CLILocalization.string("AdbDiagnosis.return-15")
        case .listedButShellDead:
            return CLILocalization.string("AdbDiagnosis.return-16")
        }
    }

    public var fixSteps: [String] {
        switch kind {
        case .ready:
            return onlyEmulator
                ? [
                    "실기기 연결 시: USB 디버깅 ON · 데이터 케이블 · 허용 팝업",
                    "에뮬로 진행: 등록 → job → run-jobs",
                    "gujo-store-ops adb 로 shell/실측 다시 확인",
                ]
                : [
                    "앱에서 등록 → 패키지 job → 실행",
                    "gujo-store-ops register-device && gujo-store-ops run-jobs",
                ]
        case .adbMissing:
            return ["brew install android-platform-tools", "gujo-store-ops adb"]
        case .noDevices:
            return [
                "데이터 USB 케이블 · USB 디버깅 ON · 파일 전송 모드",
                "adb kill-server && adb start-server && adb devices -l",
                "실측: gujo-store-ops adb (checks 에 devices/shell 표시)",
            ]
        case .unauthorized:
            return [
                "폰 팝업 ‘허용’",
                "없으면 USB 디버깅 권한 철회 후 재연결",
                "checks 에서 unauthorized → shell OK 로 바뀌는지 확인",
            ]
        case .offline:
            return ["케이블 재연결", "adb kill-server && adb start-server"]
        case .mixedNotReady:
            return ["devices 줄 state 확인", "gujo-store-ops adb"]
        case .listedButShellDead:
            return [
                "에뮬/폰 부팅 완료까지 대기",
                "adb -s <serial> shell echo ok 수동 확인",
                "실패 시 재부팅 · USB 재연결",
            ]
        }
    }

    public var headline: String {
        var parts = [kind.rawValue]
        parts.append(adbAvailable ? "adb✓" : "adb✗")
        parts.append("list \(listedReadyCount)")
        parts.append("shell \(shellOkCount)")
        if emulatorShellOkCount > 0 { parts.append("emu \(emulatorShellOkCount)") }
        if physicalShellOkCount > 0 { parts.append("phys \(physicalShellOkCount)") }
        if unauthorizedCount > 0 { parts.append("unauth \(unauthorizedCount)") }
        if offlineCount > 0 { parts.append("offline \(offlineCount)") }
        parts.append("total \(devices.count)")
        let fail = checks.filter { !$0.ok }.count
        if fail > 0 { parts.append("fail \(fail)/\(checks.count)") }
        else { parts.append("checks \(checks.count)✓") }
        return parts.joined(separator: " · ")
    }

    public var plainText: String {
        var lines: [String] = []
        lines.append(CLILocalization.format("AdbDiagnosis.string", "\(title)"))
        lines.append(summary)
        lines.append("path: \(adbPath)")
        if let v = adbVersion { lines.append("version: \(v)") }
        lines.append(headline)
        lines.append("checks:")
        for c in checks {
            lines.append("  \(c.ok ? "PASS" : "FAIL")\t\(c.id)\t\(c.title)\t\(c.detail)")
        }
        if !devices.isEmpty {
            lines.append("devices:")
            for d in devices {
                let shell = shellOkSerials.contains(d.serial ?? d.id) ? "shellOK" : "shell—"
                let emu = Self.isEmulatorSerial(d.serial ?? d.id) ? "emu" : "phys"
                lines.append("  \(d.state)\t\(shell)\t\(emu)\t\(d.serial ?? d.id)\t\(d.label)")
            }
        }
        if let raw = rawDevicesOutput, !raw.isEmpty {
            lines.append("raw adb devices -l:")
            for line in raw.split(whereSeparator: \.isNewline).prefix(20) {
                lines.append("  \(line)")
            }
        }
        lines.append("따라하기:")
        for (i, s) in fixSteps.enumerated() {
            lines.append("  \(i + 1). \(s)")
        }
        return lines.joined(separator: "\n")
    }

    public static func isEmulatorSerial(_ serial: String) -> Bool {
        let s = serial.lowercased()
        return s.hasPrefix("emulator-") || s.hasPrefix("emulator") || s.contains("emulator")
    }

    public static func classify(
        adbAvailable: Bool,
        adbPath: String,
        devices: [OpsDevice],
        shellOkSerials: Set<String> = [],
        checks: [AdbCheck] = [],
        adbVersion: String? = nil,
        rawDevicesOutput: String? = nil,
        scannedAt: Date = Date()
    ) -> AdbDiagnosis {
        guard adbAvailable else {
            return AdbDiagnosis(
                kind: .adbMissing,
                adbAvailable: false,
                adbPath: adbPath,
                checks: checks.isEmpty
                    ? [AdbCheck(id: "binary", title: CLILocalization.string("AdbDiagnosis.title"), ok: false, detail: adbPath)]
                    : checks,
                scannedAt: scannedAt
            )
        }
        let listedReady = devices.filter(\.isReady)
        let unauth = devices.filter(\.isUnauthorized)
        let offline = devices.filter(\.isOffline)
        let other = devices.filter { !$0.isReady && !$0.isUnauthorized && !$0.isOffline }
        let shellSerials = Array(shellOkSerials)
        let emuShell = shellSerials.filter { isEmulatorSerial($0) }.count
        let physShell = shellSerials.count - emuShell

        let kind: Kind
        if !shellSerials.isEmpty {
            kind = .ready
        } else if !listedReady.isEmpty {
            kind = .listedButShellDead
        } else if devices.isEmpty {
            kind = .noDevices
        } else if !unauth.isEmpty && offline.isEmpty && other.isEmpty {
            kind = .unauthorized
        } else if !offline.isEmpty && unauth.isEmpty && other.isEmpty {
            kind = .offline
        } else {
            kind = .mixedNotReady
        }

        return AdbDiagnosis(
            kind: kind,
            adbAvailable: true,
            adbPath: adbPath,
            adbVersion: adbVersion,
            devices: devices,
            listedReadyCount: listedReady.count,
            shellOkCount: shellSerials.count,
            emulatorShellOkCount: emuShell,
            physicalShellOkCount: physShell,
            unauthorizedCount: unauth.count,
            offlineCount: offline.count,
            otherNotReadyCount: other.count,
            shellOkSerials: shellSerials,
            checks: checks,
            rawDevicesOutput: rawDevicesOutput,
            scannedAt: scannedAt
        )
    }
}

extension OpsDevice {
    public var isUnauthorized: Bool {
        let s = state.lowercased()
        return s == "unauthorized" || s.contains("unauth")
    }

    public var isOffline: Bool {
        state.lowercased() == "offline"
    }

    public var isEmulator: Bool {
        AdbDiagnosis.isEmulatorSerial(serial ?? id)
    }
}
