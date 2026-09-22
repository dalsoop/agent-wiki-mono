import SwiftUI
import LocalizationKit
import LaunchAtLoginKit

public struct StandardSettingsView<Content: View>: View {
    public let config: SettingsConfig
    private let content: Content

    public init(config: SettingsConfig, @ViewBuilder content: () -> Content) {
        self.config = config
        self.content = content()
    }

    public init(config: SettingsConfig) where Content == EmptyView {
        self.config = config
        self.content = EmptyView()
    }

    private var currentLanguage: AppLanguage? {
        config.languageBinding?.wrappedValue
    }

    public var body: some View {
        Form {
            if config.showAbout {
                Section(SettingsUIKitL10n.string("settings.about", language: currentLanguage)) {
                    AboutSection(
                        appName: config.appName,
                        shortVersion: config.version,
                        build: config.buildNumber,
                        bundleID: config.bundleID,
                        showBundleID: config.showBundleID
                    )
                    if let license = config.license, !license.isEmpty {
                        LabeledContent(SettingsUIKitL10n.string("settings.license", language: currentLanguage)) {
                            Text(license)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let action = config.checkForUpdatesAction {
                        Button(SettingsUIKitL10n.string("settings.check_for_updates", language: currentLanguage)) {
                            action()
                        }
                    }
                }
            }

            if let language = config.languageBinding {
                Section(SettingsUIKitL10n.string("settings.language", language: currentLanguage)) {
                    LanguageSettingsSection(
                        SettingsUIKitL10n.string("settings.language", language: currentLanguage),
                        selection: language
                    )
                }
            }

            if let launchAtLogin = config.launchAtLoginBinding {
                Section(SettingsUIKitL10n.string("settings.launch_at_login", language: currentLanguage)) {
                    Toggle(SettingsUIKitL10n.string("settings.launch_at_login", language: currentLanguage), isOn: launchAtLogin)
                }
            } else {
                Section(SettingsUIKitL10n.string("settings.launch_at_login", language: currentLanguage)) {
                    LaunchAtLoginToggle(SettingsUIKitL10n.string("settings.launch_at_login", language: currentLanguage))
                }
            }

            content

            if !config.links.isEmpty {
                Section(SettingsUIKitL10n.string("settings.links", language: currentLanguage)) {
                    ForEach(config.links) { link in
                        Link(link.title, destination: link.url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
