import Foundation

/// 머신 고유 족보 및 식별 메타데이터 (Origin Machine Info)
public struct OriginMachineInfo: Codable, Sendable, Equatable {
    public let machineUUID: String
    public let serialNumber: String
    public let hostName: String
    public let architecture: String
    public let operatorUser: String

    public init(
        machineUUID: String = "",
        serialNumber: String = "",
        hostName: String = "",
        architecture: String = "",
        operatorUser: String = ""
    ) {
        self.machineUUID = machineUUID
        self.serialNumber = serialNumber
        self.hostName = hostName
        self.architecture = architecture
        self.operatorUser = operatorUser
    }
}

/// 백업 및 분산 저장소 참여 장비 고유 식별 정보 (Machine Identity)
public struct MachineIdentity: Identifiable, Codable, Sendable, Equatable {
    public var id: String { hardwareUUID.isEmpty ? storageFolderKey : hardwareUUID }
    public let hardwareUUID: String
    public let serialNumber: String
    public let hostName: String
    public let modelIdentifier: String
    public let architecture: String
    public let operatorUser: String
    public let storageFolderKey: String

    public init(
        hardwareUUID: String,
        serialNumber: String,
        hostName: String,
        modelIdentifier: String,
        architecture: String,
        operatorUser: String,
        storageFolderKey: String? = nil
    ) {
        self.hardwareUUID = hardwareUUID
        self.serialNumber = serialNumber
        self.hostName = hostName
        self.modelIdentifier = modelIdentifier
        self.architecture = architecture
        self.operatorUser = operatorUser

        if let storageFolderKey, !storageFolderKey.isEmpty {
            self.storageFolderKey = storageFolderKey
        } else {
            let prefix8 = hardwareUUID.isEmpty ? "unknown" : String(hardwareUUID.prefix(8)).lowercased()
            let cleanHost = hostName
                .replacingOccurrences(of: ".local", with: "")
                .replacingOccurrences(of: " ", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.storageFolderKey = "\(cleanHost)-\(prefix8)"
        }
    }
}
