import Foundation
import SwiftUI
import Testing
@testable import SettingsUIKit
import LocalizationKit

@Suite("SettingsUIStrings")
struct SettingsUIStringsTests {
    @Test("languageLabel returns fixed native names")
    func languageLabelNativeNames() {
        #expect(SettingsUIStrings.languageLabel(.system) == "System")
        #expect(SettingsUIStrings.languageLabel(.korean) == "한국어")
        #expect(SettingsUIStrings.languageLabel(.english) == "English")
    }

    @Test("languageLabel covers all AppLanguage cases")
    func languageLabelCoversAllCases() {
        for lang in AppLanguage.allCases {
            let label = SettingsUIStrings.languageLabel(lang)
            #expect(!label.isEmpty, "label for \(lang) must not be empty")
        }
    }
}

@Suite("AboutSection")
struct AboutSectionTests {
    @Test("explicit init stores values correctly")
    func explicitInit() {
        let section = AboutSection(
            appName: "TestApp",
            shortVersion: "2.1.0",
            build: "42",
            bundleID: "com.test.app",
            showBundleID: true
        )
        // AboutSection is a View — verify it can be created without crash.
        // Properties are private, so we just confirm no fatal errors on init.
        _ = section
    }

    @Test("init without bundleID does not crash")
    func initWithoutBundleID() {
        let section = AboutSection(
            appName: "Minimal",
            shortVersion: "1.0",
            build: "1"
        )
        _ = section
    }

    @Test("init with showBundleID false")
    func initHideBundleID() {
        let section = AboutSection(
            appName: "Hidden",
            shortVersion: "1.0",
            build: "1",
            bundleID: "com.hidden",
            showBundleID: false
        )
        _ = section
    }
}

@Suite("SettingsFormFooterConsumedKey")
struct SettingsFormFooterConsumedKeyTests {
    @Test("reduce ORs values together")
    func reduceOrs() {
        var value = false
        SettingsFormFooterConsumedKey.reduce(value: &value) { true }
        #expect(value)
    }

    @Test("reduce stays false when both false")
    func reduceBothFalse() {
        var value = false
        SettingsFormFooterConsumedKey.reduce(value: &value) { false }
        #expect(!value)
    }

    @Test("reduce stays true once set")
    func reduceStaysTrue() {
        var value = true
        SettingsFormFooterConsumedKey.reduce(value: &value) { false }
        #expect(value)
    }

    @Test("default value is false")
    func defaultValue() {
        #expect(!SettingsFormFooterConsumedKey.defaultValue)
    }
}

@Suite("TenantSwitcherView")
struct TenantSwitcherViewTests {
    @Test("init stores label and tenants")
    func initStoresValues() {
        var selection = "tenant-1"
        let view = TenantSwitcherView(
            label: "Tenant",
            defaultTitle: "Default",
            tenants: ["tenant-1", "tenant-2"],
            selection: .init(get: { selection }, set: { selection = $0 })
        )
        #expect(view.label == "Tenant")
        #expect(view.defaultTitle == "Default")
        #expect(view.tenants == ["tenant-1", "tenant-2"])
    }

    @Test("init with empty tenants")
    func initEmptyTenants() {
        var selection = ""
        let view = TenantSwitcherView(
            label: "T",
            defaultTitle: "All",
            tenants: [],
            selection: .init(get: { selection }, set: { selection = $0 })
        )
        #expect(view.tenants.isEmpty)
    }
}

@Suite("LanguageSettingsSection")
struct LanguageSettingsSectionTests {
    @Test("init with defaults does not crash")
    func initDefaults() {
        var lang: AppLanguage = .system
        let section = LanguageSettingsSection(
            selection: .init(get: { lang }, set: { lang = $0 })
        )
        _ = section
    }

    @Test("init with custom title and coverage")
    func initCustom() {
        var lang: AppLanguage = .korean
        let section = LanguageSettingsSection(
            "언어",
            selection: .init(get: { lang }, set: { lang = $0 }),
            coverage: nil
        )
        _ = section
    }
}

@MainActor
@Suite("StandardSettingsForm")
struct StandardSettingsFormTests {
    @Test("init with all defaults does not crash")
    func initAllDefaults() {
        let form = StandardSettingsForm {
            // empty app content
        }
        _ = form
    }

    @Test("init with language binding")
    func initWithLanguage() {
        var lang: AppLanguage = .english
        let form = StandardSettingsForm(
            language: .init(get: { lang }, set: { lang = $0 })
        ) {
            // empty
        }
        _ = form
    }

    @Test("init hiding about and launch-at-login")
    func initMinimal() {
        let form = StandardSettingsForm(
            showAbout: false,
            languageTitle: nil,
            launchAtLoginTitle: nil
        ) {
            // empty
        }
        _ = form
    }
}

@Suite("SettingsConfig & AboutConfig")
struct SettingsConfigTests {
    @Test("SettingsConfig explicit initialization")
    func settingsConfigInit() {
        let config = SettingsConfig(
            appName: "SampleApp",
            version: "1.2.3",
            buildNumber: "100",
            bundleID: "com.sample.app",
            copyright: "Copyright © 2026",
            license: "MIT",
            showAbout: true,
            showBundleID: true,
            links: [SettingsLink(title: "Docs", url: URL(string: "https://example.com") ?? URL(fileURLWithPath: "/"))]
        )
        #expect(config.appName == "SampleApp")
        #expect(config.version == "1.2.3")
        #expect(config.buildNumber == "100")
        #expect(config.bundleID == "com.sample.app")
        #expect(config.copyright == "Copyright © 2026")
        #expect(config.license == "MIT")
        #expect(config.links.count == 1)
    }

    @Test("AboutConfig explicit initialization")
    func aboutConfigInit() {
        let config = AboutConfig(
            appName: "SampleApp",
            version: "1.2.3",
            buildNumber: "100",
            bundleID: "com.sample.app",
            copyright: "Copyright © 2026",
            license: "Apache-2.0",
            systemImageName: "star.fill",
            websiteURL: URL(string: "https://example.com"),
            repositoryURL: URL(string: "https://github.com/example/repo")
        )
        #expect(config.appName == "SampleApp")
        #expect(config.version == "1.2.3")
        #expect(config.buildNumber == "100")
        #expect(config.license == "Apache-2.0")
        #expect(config.systemImageName == "star.fill")
        #expect(config.websiteURL != nil)
        #expect(config.repositoryURL != nil)
    }
}

@Suite("SettingsUIKitL10n")
struct SettingsUIKitL10nTests {
    @Test("loads embedded localization strings")
    func embeddedStrings() {
        let aboutEn = SettingsUIKitL10n.string("settings.about", language: .english)
        let aboutKo = SettingsUIKitL10n.string("settings.about", language: .korean)
        #expect(aboutEn == "About")
        #expect(aboutKo == "정보")

        let settingsEn = SettingsUIKitL10n.string("settings.title", language: .english)
        let settingsKo = SettingsUIKitL10n.string("settings.title", language: .korean)
        #expect(settingsEn == "Settings")
        #expect(settingsKo == "설정")
    }
}

@Suite("StandardViews")
struct StandardViewsTests {
    @MainActor
    @Test("StandardSettingsView renders with config")
    func standardSettingsView() {
        let config = SettingsConfig(
            appName: "TestApp",
            version: "1.0.0",
            buildNumber: "1",
            license: "MIT"
        )
        let view = StandardSettingsView(config: config) {
            Text(verbatim: "Custom Section")
        }
        #expect(view.config.appName == "TestApp")
    }

    @MainActor
    @Test("StandardAboutView renders with config")
    func standardAboutView() {
        let config = AboutConfig(
            appName: "TestApp",
            version: "1.0.0",
            buildNumber: "1"
        )
        let view = StandardAboutView(config: config)
        #expect(view.config.appName == "TestApp")
    }
}
