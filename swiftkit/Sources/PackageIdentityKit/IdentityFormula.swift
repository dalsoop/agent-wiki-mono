import Foundation

/// prefix+object → PATH CLI kebab. InteropKit `HostPlatform.liveCLIName` 이 이걸 부른다.
public enum IdentityFormula: Sendable {
    /// `app` 은 CLI 이름에 접두를 붙이지 않는다 (`Gujo VPN` → `gujo-vpn`).
    public static let appPrefix = "app"

    public static func kebab(_ objectNoun: String) -> String {
        objectNoun
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    public static func liveCLIName(prefix: String, objectNoun: String) -> String {
        let kebab = kebab(objectNoun)
        guard !kebab.isEmpty else { return "" }
        if prefix == appPrefix || prefix.isEmpty { return kebab }
        return "\(prefix)-\(kebab)"
    }

    public static func isKnownPrefix(_ prefix: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        let chars = Array(prefix)
        guard let first = chars.first, first.isLetter, first.isLowercase else { return false }
        return prefix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    public static func directoryStem(_ directory: String) -> String {
        if directory.hasSuffix("-swift") {
            return String(directory.dropLast("-swift".count))
        }
        if directory.hasSuffix("-ios") {
            return String(directory.dropLast("-ios".count))
        }
        return directory
    }
}

public enum IdentityFormulaMatch: String, Sendable, Equatable, Codable {
    case ok
    case hang
    case missingInput
    case unknownPrefix
    case drift
}

public enum IdentityCardClose: Sendable {
    /// 접힌 hang 카드. 원장이 소스 leftover 를 세지 않는다.
    public static func isHangCollapsed(_ directory: String) -> Bool {
        directory.contains("-hang-") || directory.hasPrefix("hang-")
    }
}

extension AppIdentity {
    public func formulaMatch(directory: String) -> IdentityFormulaMatch {
        if IdentityCardClose.isHangCollapsed(directory) { return .hang }
        guard let prefix, !prefix.isEmpty, let object, !object.isEmpty else {
            return .missingInput
        }
        guard IdentityFormula.isKnownPrefix(prefix) else { return .unknownPrefix }
        let minted = IdentityFormula.liveCLIName(prefix: prefix, objectNoun: object)
        if IdentityFormula.directoryStem(directory) == minted { return .ok }
        return .drift
    }
}
