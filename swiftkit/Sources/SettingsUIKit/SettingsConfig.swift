import SwiftUI
import LocalizationKit

public struct SettingsLink: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL

    public init(id: String = UUID().uuidString, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public struct SettingsConfig: @unchecked Sendable {
    public var appName: String
    public var version: String
    public var buildNumber: String
    public var bundleID: String?
    public var copyright: String?
    public var license: String?
    public var showAbout: Bool
    public var showBundleID: Bool
    public var languageBinding: Binding<AppLanguage>?
    public var launchAtLoginBinding: Binding<Bool>?
    public var checkForUpdatesAction: (@MainActor () -> Void)?
    public var links: [SettingsLink]

    public init(
        bundle: Bundle = .main,
        appName: String? = nil,
        version: String? = nil,
        buildNumber: String? = nil,
        bundleID: String? = nil,
        copyright: String? = nil,
        license: String? = nil,
        showAbout: Bool = true,
        showBundleID: Bool = true,
        languageBinding: Binding<AppLanguage>? = nil,
        launchAtLoginBinding: Binding<Bool>? = nil,
        checkForUpdatesAction: (@MainActor () -> Void)? = nil,
        links: [SettingsLink] = []
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
        self.showAbout = showAbout
        self.showBundleID = showBundleID
        self.languageBinding = languageBinding
        self.launchAtLoginBinding = launchAtLoginBinding
        self.checkForUpdatesAction = checkForUpdatesAction
        self.links = links
    }
}
