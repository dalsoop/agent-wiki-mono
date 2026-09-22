import Foundation

public enum AppIdentityKeys {
    // Info.plist keys
    public static let purposePlistKey = "AgentAppPurpose"
    public static let stateRootEnvPlistKey = "AgentAppStateRootEnv"
    public static let shortVersionPlistKey = "CFBundleShortVersionString"
    public static let bundleIdentifierPlistKey = "CFBundleIdentifier"
    public static let bundleNamePlistKey = "CFBundleName"
    public static let displayNamePlistKey = "CFBundleDisplayName"
    public static let bundleVersionPlistKey = "CFBundleVersion"
    public static let executablePlistKey = "CFBundleExecutable"

    // package-identity.json keys
    public static let identityPurposeKey = "purpose"
    public static let identityStateRootEnvKey = "state_root_env"
    public static let identityCLIKey = "cli"
    public static let identityCLIProductKey = "cli_product"
    public static let identityDisplayKey = "display"
    public static let identityFormerCLINamesKey = "former_cli_names"
    public static let identityPrefixKey = "prefix"
    public static let identityObjectKey = "object"
}
