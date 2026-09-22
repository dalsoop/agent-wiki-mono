import Foundation
import MoneyInflowKit
import StateRootKit

public struct MoneySourceProfileConfig: Codable, Sendable, Equatable {
    public var profile: ApplicantProfile
    public var crtfcKey: String

    public init(profile: ApplicantProfile = .blank, crtfcKey: String = "") {
        self.profile = profile
        self.crtfcKey = crtfcKey
    }

    public init(crtfcKey: String, profile: ApplicantProfile = .blank) {
        self.profile = profile
        self.crtfcKey = crtfcKey
    }
}

public typealias GovernmentProgramProfileConfig = MoneySourceProfileConfig
public typealias SubsidyProfileConfig = MoneySourceProfileConfig
public typealias LoanProfileConfig = MoneySourceProfileConfig
public typealias TaxBenefitProfileConfig = MoneySourceProfileConfig

public enum MoneySourceConfigStore {
    public static func url(for fileName: String) -> URL {
        StateRootKit.url(".swift-app-state").appendingPathComponent(fileName)
    }

    public static func load<T: Codable>(_ type: T.Type = T.self, from fileName: String, `default`: () -> T) -> T {
        let file = url(for: fileName)
        guard let data = FileLoad.data(contentsOf: file),
              let decoded = FileLoad.decode(type, from: data) else {
            return `default`()
        }
        return decoded
    }

    public static func save<T: Codable>(_ value: T, to fileName: String) throws {
        let file = url(for: fileName)
        let dir = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(value).write(to: file, options: .atomic)
    }
}

public enum GovernmentProgramConfigStore {
    public static let fileName = "money-source-government-program-lookup-config.json"
    public static var url: URL { MoneySourceConfigStore.url(for: fileName) }
    public static func load() -> GovernmentProgramProfileConfig {
        MoneySourceConfigStore.load(from: fileName, default: { GovernmentProgramProfileConfig() })
    }
    public static func save(_ cfg: GovernmentProgramProfileConfig) throws {
        try MoneySourceConfigStore.save(cfg, to: fileName)
    }
}

public enum SubsidyConfigStore {
    public static let fileName = "money-source-subsidy-lookup-config.json"
    public static var url: URL { MoneySourceConfigStore.url(for: fileName) }
    public static func load() -> SubsidyProfileConfig {
        MoneySourceConfigStore.load(from: fileName, default: { SubsidyProfileConfig() })
    }
    public static func save(_ cfg: SubsidyProfileConfig) throws {
        try MoneySourceConfigStore.save(cfg, to: fileName)
    }
}

public enum LoanConfigStore {
    public static let fileName = "money-source-loan-lookup-config.json"
    public static var url: URL { MoneySourceConfigStore.url(for: fileName) }
    public static func load() -> LoanProfileConfig {
        MoneySourceConfigStore.load(from: fileName, default: { LoanProfileConfig() })
    }
    public static func save(_ cfg: LoanProfileConfig) throws {
        try MoneySourceConfigStore.save(cfg, to: fileName)
    }
}

public enum TaxBenefitConfigStore {
    public static let fileName = "money-source-tax-benefit-lookup-config.json"
    public static var url: URL { MoneySourceConfigStore.url(for: fileName) }
    nonisolated(unsafe) public static var lastLoadErrorDescription: String? = nil

    public static func load() -> TaxBenefitProfileConfig {
        lastLoadErrorDescription = nil
        let file = url
        guard FileManager.default.fileExists(atPath: file.path) else {
            return TaxBenefitProfileConfig()
        }
        guard let data = FileLoad.data(contentsOf: file) else {
            lastLoadErrorDescription = "Failed to read config data"
            return TaxBenefitProfileConfig()
        }
        guard let decoded = FileLoad.decode(TaxBenefitProfileConfig.self, from: data) else {
            lastLoadErrorDescription = "Failed to decode config JSON"
            return TaxBenefitProfileConfig()
        }
        return decoded
    }
    public static func save(_ cfg: TaxBenefitProfileConfig) throws {
        try MoneySourceConfigStore.save(cfg, to: fileName)
    }
}
