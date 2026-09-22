import SwiftUI

public struct AboutConfig: Sendable {
    public var appName: String
    public var version: String
    public var buildNumber: String
    public var bundleID: String?
    public var copyright: String?
    public var license: String?
    public var systemImageName: String?
    public var websiteURL: URL?
    public var repositoryURL: URL?
    public var checkForUpdatesAction: (@MainActor @Sendable () -> Void)?

    public init(
        bundle: Bundle = .main,
        appName: String? = nil,
        version: String? = nil,
        buildNumber: String? = nil,
        bundleID: String? = nil,
        copyright: String? = nil,
        license: String? = nil,
        systemImageName: String? = nil,
        websiteURL: URL? = nil,
        repositoryURL: URL? = nil,
        checkForUpdatesAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.appName = appName
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
        self.version = version
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "1.0.0"
        self.buildNumber = buildNumber
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "1"
        self.bundleID = bundleID ?? bundle.bundleIdentifier
        self.copyright = copyright ?? (bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)
        self.license = license
        self.systemImageName = systemImageName
        self.websiteURL = websiteURL
        self.repositoryURL = repositoryURL
        self.checkForUpdatesAction = checkForUpdatesAction
    }
}
