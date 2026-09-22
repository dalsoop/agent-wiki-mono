import Foundation
import OnboardingKit
#if os(macOS)
import AppKit
#endif

#if os(macOS)
public enum OnboardingSystemSettingsOpener {
    @MainActor
    public static func open(pane: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?\(pane)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [urls[0]]
        do {
            try proc.run()
        } catch {
            fputs("openSystemSettings: failed to run /usr/bin/open: \(error)\n", stderr)
        }
    }
}
#endif

extension OnboardingItem {
    public static func fullDiskAccess(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_AllFiles")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "fullDiskAccess",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.full_disk_access.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.full_disk_access.detail"),
            symbol: "internaldrive",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func accessibility(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_Accessibility")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "accessibility",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.accessibility.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.accessibility.detail"),
            symbol: "hand.raised",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func screenRecording(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_ScreenCapture")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "screenRecording",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.screen_recording.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.screen_recording.detail"),
            symbol: "record.circle",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func camera(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_Camera")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "camera",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.camera.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.camera.detail"),
            symbol: "camera",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func microphone(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_Microphone")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "microphone",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.microphone.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.microphone.detail"),
            symbol: "mic",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func inputMonitoring(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_ListenEvent")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "inputMonitoring",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.input_monitoring.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.input_monitoring.detail"),
            symbol: "keyboard",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func location(
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        let resolvedAction: (@MainActor @Sendable () -> Void)?
        if let onAction {
            resolvedAction = onAction
        } else {
            #if os(macOS)
            resolvedAction = {
                Task { @MainActor in
                    OnboardingSystemSettingsOpener.open(pane: "Privacy_LocationServices")
                }
            }
            #else
            resolvedAction = nil
            #endif
        }

        return OnboardingItem(
            id: "location",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.location.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.location.detail"),
            symbol: "location",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.open_settings"),
            action: resolvedAction
        )
    }

    public static func defaults(
        done: Bool = true,
        required: Bool = false,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        OnboardingItem(
            id: "defaults",
            done: done,
            required: required,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.defaults.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.defaults.detail"),
            symbol: "gearshape.2",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.apply_now"),
            action: onAction
        )
    }

    public static func required(
        done: Bool,
        title: String? = nil,
        detail: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        OnboardingItem(
            id: "required",
            done: done,
            required: true,
            title: title ?? OnboardingUIKitL10n.string("onboarding.item.required.title"),
            detail: detail ?? OnboardingUIKitL10n.string("onboarding.item.required.detail"),
            symbol: "checkmark.shield",
            actionTitle: actionTitle ?? OnboardingUIKitL10n.string("onboarding.action.enable_now"),
            action: onAction
        )
    }

    public static func feature(
        symbol: String,
        title: String,
        detail: String
    ) -> OnboardingItem {
        OnboardingItem(
            id: "feature_\(symbol)_\(title)",
            done: true,
            required: false,
            title: title,
            detail: detail,
            symbol: symbol,
            actionTitle: nil,
            action: nil
        )
    }

    public static func custom(
        id: String,
        title: String,
        detail: String,
        done: Bool,
        required: Bool = true,
        symbol: String? = nil,
        actionTitle: String? = nil,
        onAction: (@MainActor @Sendable () -> Void)? = nil
    ) -> OnboardingItem {
        OnboardingItem(
            id: id,
            done: done,
            required: required,
            title: title,
            detail: detail,
            symbol: symbol,
            actionTitle: actionTitle,
            action: onAction
        )
    }
}
