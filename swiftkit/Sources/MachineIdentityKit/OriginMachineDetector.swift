import Foundation
import CommandKit

/// 하드웨어 고유 식별 및 머신 족보 탐지기
public struct OriginMachineDetector: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// 현재 Mac의 고유 식별 정보 수집
    public func detectCurrentMachine() async -> OriginMachineInfo {
        let uuid = await extractHardwareUUID()
        let serial = await extractSerialNumber()
        let host = ProcessInfo.processInfo.hostName
        let arch = getArchitecture()
        let user = NSUserName()

        return OriginMachineInfo(
            machineUUID: uuid,
            serialNumber: serial,
            hostName: host,
            architecture: arch,
            operatorUser: user
        )
    }

    /// 현재 Mac의 고유 식별 정보(MachineIdentity) 수집 (IOPlatformUUID 기반)
    public func detectMachineIdentity(storageFolderKeyOverride: String? = nil) async -> MachineIdentity {
        let uuid = await extractHardwareUUID()
        let serial = await extractSerialNumber()
        let host = ProcessInfo.processInfo.hostName
        let model = await extractModelIdentifier()
        let arch = getArchitecture()
        let user = NSUserName()

        return MachineIdentity(
            hardwareUUID: uuid,
            serialNumber: serial,
            hostName: host,
            modelIdentifier: model,
            architecture: arch,
            operatorUser: user,
            storageFolderKey: storageFolderKeyOverride
        )
    }

    public func extractModelIdentifier() async -> String {
        if let model = extractModelFromSysctl() {
            return model
        }
        return await extractModelFromIoreg()
    }

    private func extractModelFromSysctl() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let trimmed = model.prefix(while: { $0 != 0 })
        let u8 = trimmed.map { UInt8(bitPattern: $0) }
        let str = String(decoding: u8, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? nil : str
    }

    private func extractModelFromIoreg() async -> String {
        let result = await runner.run(
            "/usr/sbin/ioreg",
            ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeout: 5.0
        )
        guard result.ok else { return "Mac" }
        for line in result.stdout.components(separatedBy: .newlines) {
            guard line.contains("\"model\" = <\"") else { continue }
            let parts = line.components(separatedBy: "\"model\" = <\"")
            guard parts.count >= 2 else { continue }
            return parts[1].replacingOccurrences(of: "\">", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Mac"
    }

    private func extractHardwareUUID() async -> String {
        let result = await runner.run(
            "/usr/sbin/ioreg",
            ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeout: 5.0
        )
        guard result.ok else { return "" }
        for line in result.stdout.components(separatedBy: .newlines) {
            if line.contains("IOPlatformUUID") {
                let parts = line.components(separatedBy: "\" = \"")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t\n\r"))
                }
            }
        }
        return ""
    }

    private func extractSerialNumber() async -> String {
        let result = await runner.run(
            "/usr/sbin/ioreg",
            ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeout: 5.0
        )
        guard result.ok else { return "" }
        for line in result.stdout.components(separatedBy: .newlines) {
            if line.contains("IOPlatformSerialNumber") {
                let parts = line.components(separatedBy: "\" = \"")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t\n\r"))
                }
            }
        }
        return ""
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
