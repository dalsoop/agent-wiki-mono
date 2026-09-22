import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct StandardAboutView: View {
    public let config: AboutConfig

    public init(config: AboutConfig = AboutConfig()) {
        self.config = config
    }

    public var body: some View {
        VStack(spacing: 16) {
            #if canImport(AppKit)
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else if let icon = config.systemImageName {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }
            #else
            if let icon = config.systemImageName {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }
            #endif

            VStack(spacing: 4) {
                Text(config.appName)
                    .font(.title2.bold())
                Text(verbatim: "\(SettingsUIKitL10n.string("settings.version")) \(config.version) (\(config.buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let bundleID = config.bundleID {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            if let license = config.license {
                Text(license)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let copyright = config.copyright {
                Text(copyright)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let site = config.websiteURL {
                    Link(SettingsUIKitL10n.string("settings.website"), destination: site)
                        .font(.caption)
                }
                if let repo = config.repositoryURL {
                    Link(SettingsUIKitL10n.string("settings.repository"), destination: repo)
                        .font(.caption)
                }
            }

            if let checkUpdates = config.checkForUpdatesAction {
                Button(SettingsUIKitL10n.string("settings.check_for_updates")) {
                    checkUpdates()
                }
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(minWidth: 280, maxWidth: 360)
    }
}
