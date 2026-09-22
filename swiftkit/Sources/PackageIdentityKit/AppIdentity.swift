import Foundation

public struct AppIdentity: Sendable, Equatable {
    public var purpose: String?
    public var stateRootEnv: String?
    public var version: String?
    public var bundleIdentifier: String?
    public var bundleName: String?
    public var bundleDisplayName: String?
    public var bundleVersion: String?
    public var executableName: String?
    public var cli: String?
    public var cliProduct: String?
    public var guiProduct: String?
    public var display: String?
    public var formerCLINames: [String]
    public var extraCLIs: [String]
    public var appAliases: [String]

    public var sourceURL: URL?
    public var plistURL: URL?
    public var packageIdentityURL: URL?

    public var shortVersion: String? { version }
    public var displayName: String? { display ?? bundleDisplayName ?? bundleName }
    public var prefix: String? { identityStrings[AppIdentityKeys.identityPrefixKey] }
    public var object: String? { identityStrings[AppIdentityKeys.identityObjectKey] }

    private var plistStrings: [String: String]
    private var identityStrings: [String: String]

    public init(
        purpose: String? = nil,
        stateRootEnv: String? = nil,
        version: String? = nil,
        bundleIdentifier: String? = nil,
        bundleName: String? = nil,
        bundleDisplayName: String? = nil,
        bundleVersion: String? = nil,
        executableName: String? = nil,
        cli: String? = nil,
        cliProduct: String? = nil,
        guiProduct: String? = nil,
        display: String? = nil,
        formerCLINames: [String] = [],
        extraCLIs: [String] = [],
        appAliases: [String] = [],
        sourceURL: URL? = nil,
        plistURL: URL? = nil,
        packageIdentityURL: URL? = nil,
        plistStrings: [String: String] = [:],
        identityStrings: [String: String] = [:]
    ) {
        self.purpose = purpose
        self.stateRootEnv = stateRootEnv
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.bundleName = bundleName
        self.bundleDisplayName = bundleDisplayName
        self.bundleVersion = bundleVersion
        self.executableName = executableName
        self.cli = cli
        self.cliProduct = cliProduct
        self.guiProduct = guiProduct
        self.display = display
        self.formerCLINames = formerCLINames
        self.extraCLIs = extraCLIs
        self.appAliases = appAliases
        self.sourceURL = sourceURL
        self.plistURL = plistURL
        self.packageIdentityURL = packageIdentityURL
        self.plistStrings = plistStrings
        self.identityStrings = identityStrings
    }

    public init(
        plist: [String: Any]? = nil,
        json: [String: Any]? = nil,
        sourceURL: URL? = nil,
        plistURL: URL? = nil,
        packageIdentityURL: URL? = nil
    ) {
        let pStrings = Self.extractStrings(from: plist)
        let iStrings = Self.extractStrings(from: json)

        let purpose = pStrings[AppIdentityKeys.purposePlistKey]
            ?? iStrings[AppIdentityKeys.identityPurposeKey]
        let stateRoot = pStrings[AppIdentityKeys.stateRootEnvPlistKey]
            ?? iStrings[AppIdentityKeys.identityStateRootEnvKey]
        let version = pStrings[AppIdentityKeys.shortVersionPlistKey]
            ?? iStrings["version"]
        let cli = iStrings[AppIdentityKeys.identityCLIKey]
            ?? iStrings[AppIdentityKeys.identityCLIProductKey]
        let display = iStrings[AppIdentityKeys.identityDisplayKey]
            ?? pStrings[AppIdentityKeys.displayNamePlistKey]
            ?? pStrings[AppIdentityKeys.bundleNamePlistKey]

        self.init(
            purpose: purpose,
            stateRootEnv: stateRoot,
            version: version,
            bundleIdentifier: pStrings[AppIdentityKeys.bundleIdentifierPlistKey],
            bundleName: pStrings[AppIdentityKeys.bundleNamePlistKey],
            bundleDisplayName: pStrings[AppIdentityKeys.displayNamePlistKey],
            bundleVersion: pStrings[AppIdentityKeys.bundleVersionPlistKey],
            executableName: pStrings[AppIdentityKeys.executablePlistKey],
            cli: cli,
            cliProduct: iStrings[AppIdentityKeys.identityCLIProductKey],
            guiProduct: iStrings["gui_product"],
            display: display,
            formerCLINames: Self.stringArray(json?[AppIdentityKeys.identityFormerCLINamesKey]),
            extraCLIs: Self.stringArray(json?["extra_clis"]),
            appAliases: Self.stringArray(json?["app_aliases"]),
            sourceURL: sourceURL,
            plistURL: plistURL,
            packageIdentityURL: packageIdentityURL,
            plistStrings: pStrings,
            identityStrings: iStrings
        )
    }

    public init(json: [String: Any]) {
        self.init(plist: nil, json: json)
    }

    public init(json: [String: Any], packageIdentityURL: URL) {
        self.init(plist: nil, json: json, packageIdentityURL: packageIdentityURL)
    }

    public init(plist: [String: Any]) {
        self.init(plist: plist, json: nil)
    }

    public func value(plistKey: String, identityKey: String) -> String? {
        if let fromPlist = plistValue(key: plistKey) {
            return fromPlist
        }
        if let fromIdentity = identityValue(key: identityKey) {
            return fromIdentity
        }
        return nil
    }

    public func plistValue(key: String) -> String? {
        plistStrings[key]
    }

    public func identityValue(key: String) -> String? {
        identityStrings[key]
    }

    public static func load(
        plistURL: URL? = nil,
        identityURL: URL? = nil,
        sourceURL: URL? = nil
    ) -> AppIdentity? {
        let plistDict = readPlist(at: plistURL)
        let identityDict = readJSON(at: identityURL)

        guard plistDict != nil || identityDict != nil else {
            return nil
        }

        return AppIdentity(
            plist: plistDict,
            json: identityDict,
            sourceURL: sourceURL,
            plistURL: plistURL,
            packageIdentityURL: identityURL
        )
    }

    private static func readPlist(at url: URL?) -> [String: Any]? {
        guard let url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func readJSON(at url: URL?) -> [String: Any]? {
        guard let url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func extractStrings(from dict: [String: Any]?) -> [String: String] {
        guard let dict else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in dict {
            if let trimmed = trimmedString(v) {
                result[k] = trimmed
            }
        }
        return result
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let list = value as? [Any] else { return [] }
        var result: [String] = []
        for item in list {
            if let str = trimmedString(item) {
                result.append(str)
            }
        }
        return result
    }
}
