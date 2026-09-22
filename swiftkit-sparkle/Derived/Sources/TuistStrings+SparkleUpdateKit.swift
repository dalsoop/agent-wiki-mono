// swiftlint:disable:this file_name
// swiftlint:disable all
// swift-format-ignore-file
// swiftformat:disable all
// Generated using tuist — https://github.com/tuist/tuist

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name
public enum SparkleUpdateKitStrings: Sendable {

  public enum Sparkle: Sendable {
    /// Check for updates automatically
    public static let autoCheck = SparkleUpdateKitStrings.tr("Localizable", "sparkle.auto_check")
    /// Looks for a newer build on the public feed.
    public static let checkHelp = SparkleUpdateKitStrings.tr("Localizable", "sparkle.check_help")
    /// Check for Updates…
    public static let checkNow = SparkleUpdateKitStrings.tr("Localizable", "sparkle.check_now")
    /// This install has no Sparkle channel. Ship a build that has SUFeedURL and Sparkle.framework.
    public static let noChannelHelp = SparkleUpdateKitStrings.tr("Localizable", "sparkle.no_channel_help")
    /// No update channel on this install. Run app-build-manager ship, then reopen Settings.
    public static let noChannelVisible = SparkleUpdateKitStrings.tr("Localizable", "sparkle.no_channel_visible")
    /// Settings…
    public static let openSettings = SparkleUpdateKitStrings.tr("Localizable", "sparkle.open_settings")
    /// Updates
    public static let sectionTitle = SparkleUpdateKitStrings.tr("Localizable", "sparkle.section_title")
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name

// MARK: - Implementation Details

extension SparkleUpdateKitStrings {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: nil, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
// swiftformat:enable all
// swiftlint:enable all
