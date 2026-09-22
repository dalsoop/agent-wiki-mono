import Foundation

/// One declared need for an app (binary on PATH, mount host, etc.).
public struct DependencyNeed: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: DependencyKind
    /// Path, binary name, bundle id, port number string, env key, etc.
    public var value: String
    public var label: String
    public var optional: Bool

    public init(
        id: String = UUID().uuidString,
        kind: DependencyKind,
        value: String,
        label: String? = nil,
        optional: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.label = label ?? value
        self.optional = optional
    }
}

public enum DependencyKind: String, Codable, CaseIterable, Sendable {
    /// Executable name searched on common PATH prefixes.
    case binary
    /// Absolute path must exist.
    case path
    /// Bundle id must resolve to an installed .app.
    case bundle
    /// TCP port open on localhost (string "445").
    case port
    /// Environment variable non-empty.
    case env
}

/// App row in the dependency catalog.
public struct AppDependencySpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    /// Optional CFBundleIdentifier / StateMirror app key.
    public var bundleID: String?
    public var needs: [DependencyNeed]
    public var enabled: Bool

    public init(
        id: String,
        displayName: String,
        bundleID: String? = nil,
        needs: [DependencyNeed] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.needs = needs
        self.enabled = enabled
    }
}

public struct DependencyCatalog: Codable, Equatable, Sendable {
    public var version: Int
    public var apps: [AppDependencySpec]

    public init(version: Int = 1, apps: [AppDependencySpec] = []) {
        self.version = version
        self.apps = apps
    }

    /// Built-in defaults for well-known mono apps (overridable by user file).
    public static var builtIn: DependencyCatalog {
        DependencyCatalog(apps: [
            AppDependencySpec(
                id: "mounter",
                displayName: "Mounter",
                bundleID: "net.ranode.mounter",
                needs: [
                    DependencyNeed(kind: .binary, value: "rclone", label: "rclone (nfsmount)"),
                    DependencyNeed(kind: .path, value: "/usr/bin/smbutil", label: "smbutil", optional: true),
                ]
            ),
            AppDependencySpec(
                id: "vpn-wireguard",
                displayName: "VPN WireGuard",
                bundleID: "net.ranode.vpn-wireguard",
                needs: [
                    DependencyNeed(kind: .binary, value: "wg", label: "wg CLI", optional: true),
                ]
            ),
            AppDependencySpec(
                id: "app-build-manager",
                displayName: "App Build Manager",
                bundleID: "net.ranode.app-build-manager",
                needs: [
                    DependencyNeed(kind: .path, value: "/usr/bin/codesign", label: "codesign"),
                    DependencyNeed(kind: .path, value: "/usr/bin/security", label: "security"),
                ]
            ),
        ])
    }

    /// User overlay wins on same `id`; unknown ids from user are appended.
    public func merging(overlay: DependencyCatalog) -> DependencyCatalog {
        var byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        for app in overlay.apps {
            byID[app.id] = app
        }
        return DependencyCatalog(version: max(version, overlay.version), apps: byID.values.sorted { $0.id < $1.id })
    }
}
