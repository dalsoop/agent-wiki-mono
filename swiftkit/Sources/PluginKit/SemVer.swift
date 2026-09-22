import Foundation

/// 플러그인 버전 비교 및 호환성 검증을 위한 표준 시맨틱 버전 (SemVer 2.0.0) 구조체
public struct SemVer: Comparable, Sendable, CustomStringConvertible, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    
    public init(_ versionString: String) {
        let cleaned = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        
        let parts = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let mainParts = parts.first?.split(separator: ".") ?? []
        
        self.major = mainParts.count > 0 ? Int(mainParts[0]) ?? 0 : 0
        self.minor = mainParts.count > 1 ? Int(mainParts[1]) ?? 0 : 0
        self.patch = mainParts.count > 2 ? Int(mainParts[2]) ?? 0 : 0
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
    }
    
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }
    
    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease, !prerelease.isEmpty {
            return "\(base)-\(prerelease)"
        }
        return base
    }
    
    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // Prerelease 비교 (prerelease가 없는 정식 버전이 더 높음)
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if let lp = lhs.prerelease, let rp = rhs.prerelease {
            return lp < rp
        }
        return false
    }
    
    /// 주어진 버전 제약조건(minVersion, maxVersion)을 만족하는지 검사
    public func satisfies(minVersion: String? = nil, maxVersion: String? = nil) -> Bool {
        if let minStr = minVersion, !minStr.isEmpty {
            let minVer = SemVer(minStr)
            if self < minVer { return false }
        }
        if let maxStr = maxVersion, !maxStr.isEmpty {
            let maxVer = SemVer(maxStr)
            if self > maxVer { return false }
        }
        return true
    }
}

/// 플러그인이 요구하는 의존성 명세 (버전 제약조건 포함)
public struct PluginDependencyRequirement: Sendable, Equatable {
    public let pluginId: String
    public let minVersion: String?
    public let maxVersion: String?
    
    public init(pluginId: String, minVersion: String? = nil, maxVersion: String? = nil) {
        self.pluginId = pluginId
        self.minVersion = minVersion
        self.maxVersion = maxVersion
    }
}
