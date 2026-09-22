import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// 실행 줄 한 줄. 함대 앱 모델에 의존하지 않는다.
public struct FleetDeskNamedApp: Sendable, Equatable, Codable {
    public var bundleId: String
    public var name: String

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}

public enum FleetDeskDockPresence: String, Sendable, Equatable, Codable {
    /// 시스템 Dock 타일이 보이는 Foreground 앱.
    case onDock
    /// UIElement / accessory — Dock에 없음.
    case hidden
    /// lsappinfo 에 없음. 프로세스만 있고 타일은 없음.
    case unknown
}

public struct FleetDeskLiveRow: Sendable, Equatable, Codable {
    public var bundleId: String
    public var name: String
    public var intendedHide: Bool
    public var liveHidden: Bool
    public var onDock: Bool

    public init(
        bundleId: String,
        name: String,
        intendedHide: Bool,
        liveHidden: Bool,
        onDock: Bool? = nil
    ) {
        self.bundleId = bundleId
        self.name = name
        self.intendedHide = intendedHide
        self.liveHidden = liveHidden
        self.onDock = onDock ?? (!liveHidden)
    }

    /// Dock에 실제로 남아 있는 숨김 대상만 대기다. 유령 프로세스는 세지 않는다.
    public var pending: Bool { intendedHide && onDock }
}

public struct FleetDeskLiveReport: Sendable, Equatable, Codable {
    public var hideEnabled: Bool
    public var hideTargets: Int
    public var applied: Int
    public var pending: Int
    public var rows: [FleetDeskLiveRow]

    public init(
        hideEnabled: Bool,
        hideTargets: Int,
        applied: Int,
        pending: Int,
        rows: [FleetDeskLiveRow]
    ) {
        self.hideEnabled = hideEnabled
        self.hideTargets = hideTargets
        self.applied = applied
        self.pending = pending
        self.rows = rows
    }

    public static func tally(
        apps: [FleetDeskNamedApp],
        hideEnabled: Bool,
        dockBundleIds: [String] = FleetDeskPolicy.defaultDockBundleIds,
        liveHidden: (String) -> Bool,
        onDock: ((String) -> Bool)? = nil
    ) -> FleetDeskLiveReport {
        let rows = apps.map { app in
            let intend = FleetDeskPolicy.shouldHideDockIcon(
                bundleId: app.bundleId,
                hideEnabled: hideEnabled,
                dockBundleIds: dockBundleIds
            )
            let hidden = liveHidden(app.bundleId)
            let docked = onDock?(app.bundleId) ?? !hidden
            return FleetDeskLiveRow(
                bundleId: app.bundleId,
                name: app.name,
                intendedHide: intend,
                liveHidden: hidden,
                onDock: docked
            )
        }
        let targets = rows.filter(\.intendedHide)
        let applied = targets.filter(\.liveHidden).count
        let pending = targets.filter(\.pending).count
        return FleetDeskLiveReport(
            hideEnabled: hideEnabled,
            hideTargets: targets.count,
            applied: applied,
            pending: pending,
            rows: rows
        )
    }
}

/// lsappinfo `type=UIElement` 실측. JSON 의도·Dock 핀과 섞지 않는다.
public enum FleetDeskLiveProbe {
    private final class CacheBox: @unchecked Sendable {
        let lock = NSLock()
        var map: [String: FleetDeskDockPresence] = [:]
    }

    private static let cache = CacheBox()

    public static func resetCache() {
        cache.lock.lock()
        cache.map.removeAll()
        cache.lock.unlock()
    }

    public static func parseUIElement(_ text: String) -> Bool {
        parsePresence(text) == .hidden
    }

    public static func parsePresence(_ text: String) -> FleetDeskDockPresence {
        if text.contains("type=\"UIElement\"") { return .hidden }
        if text.contains("type=\"Foreground\"") { return .onDock }
        return .unknown
    }

    public static func isLiveHidden(bundleId: String) -> Bool {
        switch presence(bundleId: bundleId) {
        case .hidden: return true
        case .onDock, .unknown: return false
        }
    }

    public static func isOnDock(bundleId: String) -> Bool {
        presence(bundleId: bundleId) == .onDock
    }

    public static func isUIElement(bundleId: String) -> Bool {
        isLiveHidden(bundleId: bundleId)
    }

    public static func presence(bundleId: String) -> FleetDeskDockPresence {
        let key = bundleId.lowercased()
        cache.lock.lock()
        if let cached = cache.map[key] {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()
        var value = parsePresence(probeText(bundleId: bundleId))
        #if canImport(AppKit)
        if value == .unknown {
            value = workspacePresence(bundleId: bundleId)
        }
        #endif
        cache.lock.lock()
        cache.map[key] = value
        cache.lock.unlock()
        return value
    }

    private static func probeText(bundleId: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        process.arguments = ["info", "-app", bundleId]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    #if canImport(AppKit)
    private static func workspacePresence(bundleId: String) -> FleetDeskDockPresence {
        let match = NSWorkspace.shared.runningApplications.first { app in
            guard let id = app.bundleIdentifier else { return false }
            return id.caseInsensitiveCompare(bundleId) == .orderedSame
        }
        guard let match else { return .unknown }
        switch match.activationPolicy {
        case .accessory, .prohibited: return .hidden
        case .regular: return .onDock
        @unknown default: return .unknown
        }
    }
    #endif
}
