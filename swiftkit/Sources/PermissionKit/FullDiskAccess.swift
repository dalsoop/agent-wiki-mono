import AppKit
import Foundation

/// macOS does not expose an exact Full Disk Access authorization API. This status
/// therefore describes the result of a protected-directory probe, not TCC state.
public enum FullDiskAccessStatus: String, Codable, Sendable {
    case likelyGranted
    case likelyDenied
    case unknown
}

public enum FullDiskAccess {
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    public static func status(
        probe: @Sendable () -> Bool?
    ) -> FullDiskAccessStatus {
        switch probe() {
        case true: .likelyGranted
        case false: .likelyDenied
        case nil: .unknown
        }
    }

    /// Probes the first protected directory that exists on this Mac. A successful
    /// listing is a strong signal of access; only permission errors are treated as
    /// denial because other failures do not describe Full Disk Access reliably.
    public static func defaultStatus(
        fileManager: FileManager = .default
    ) -> FullDiskAccessStatus {
        let libraryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        let protectedURLs = ["Safari", "Mail"].map {
            libraryURL.appendingPathComponent($0, isDirectory: true)
        }

        guard let probeURL = protectedURLs.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            return .unknown
        }

        do {
            _ = try fileManager.contentsOfDirectory(
                at: probeURL,
                includingPropertiesForKeys: nil
            )
            return .likelyGranted
        } catch {
            return isPermissionError(error) ? .likelyDenied : .unknown
        }
    }

    @MainActor public static func openSettings() {
        PrivacySettingsOpener.open(primaryURLString: settingsURLString)
    }

    @MainActor public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { runningApplication, error in
            guard shouldTerminateAfterRelaunch(
                hasRunningApplication: runningApplication != nil,
                error: error
            ) else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    static func shouldTerminateAfterRelaunch(
        hasRunningApplication: Bool,
        error: Error?
    ) -> Bool {
        hasRunningApplication && error == nil
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        }
        return error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoPermissionError
    }
}
