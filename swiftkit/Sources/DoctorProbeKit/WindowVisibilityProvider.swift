import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

/// Snapshot of a running application used by window-visibility diagnosis.
public struct WindowVisibilityApp: Sendable, Equatable {
    public var name: String
    public var pid: Int32
    public var bundlePath: String?

    public init(name: String, pid: Int32, bundlePath: String? = nil) {
        self.name = name
        self.pid = pid
        self.bundlePath = bundlePath
    }
}

/// Snapshot of a CG window owned by some process.
public struct WindowVisibilityWindow: Sendable, Equatable {
    public var ownerPID: Int32
    public var ownerName: String
    public var layer: Int

    public init(ownerPID: Int32, ownerName: String, layer: Int = 0) {
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.layer = layer
    }
}

/// "앱이 실행됐는데 창이 안 뜬다" 를 CGWindowList + AX 권한으로 5초 안에 판정한다.
///
/// **핵심**: `CGWindowListCopyWindowInfo` 는 접근성 권한 없이도 창 목록을 읽는다.
/// `AXIsProcessTrusted()` 로 권한 여부를 따로 확인해, 창이 없는 것과 권한이 없어
/// 못 보는 것을 구분한다.
///
/// 판정 로직:
/// ```
/// 프로세스 없음                     → fail "실행 안 됨 (크래시 확인)"
/// 프로세스 O + LSUIElement=true     → ok   "메뉴바 앱 (창 없는 게 정상)"
/// 프로세스 O + 창 O                 → ok   "정상"
/// 프로세스 O + 창 X + AX권한 O      → fail "창이 안 뜬다 — 앱 버그"
/// 프로세스 O + 창 X + AX권한 X      → warn "판정 불가 — 접근성 권한 필요"
/// ```
public struct WindowVisibilityDoctorProvider: DoctorProvider {
    public let id = "window-visibility"

    private let subjects: [String]
    private let listRunning: @Sendable () -> [WindowVisibilityApp]
    private let listWindows: @Sendable () -> [WindowVisibilityWindow]
    private let isAXTrusted: @Sendable () -> Bool
    private let readLSUIElement: @Sendable (String?) -> Bool

    public init(
        subjects: [String],
        listRunning: @escaping @Sendable () -> [WindowVisibilityApp] = Self.defaultListRunning,
        listWindows: @escaping @Sendable () -> [WindowVisibilityWindow] = Self.defaultListWindows,
        isAXTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        readLSUIElement: @escaping @Sendable (String?) -> Bool = Self.defaultReadLSUIElement
    ) {
        self.subjects = subjects
        self.listRunning = listRunning
        self.listWindows = listWindows
        self.isAXTrusted = isAXTrusted
        self.readLSUIElement = readLSUIElement
    }

    public func run() async -> [DoctorFinding] {
        guard !subjects.isEmpty else { return [] }
        let apps = listRunning()
        let windows = listWindows()
        let ax = isAXTrusted()
        return subjects.map { subject in
            diagnose(
                subject: subject,
                apps: apps,
                windows: windows,
                axTrusted: ax
            )
        }
    }

    /// Single-subject diagnosis (CLI / unit tests).
    public func diagnose(
        subject: String,
        apps: [WindowVisibilityApp],
        windows: [WindowVisibilityWindow],
        axTrusted: Bool
    ) -> DoctorFinding {
        let matches = apps.filter { Self.matches(subject: subject, app: $0) }
        guard let app = matches.first else {
            return DoctorFinding(
                category: .runtime,
                severity: .fail,
                body: .init(
                    subject: subject,
                    title: "실행 안 됨 (크래시 확인)",
                    detail: "프로세스 목록에 '\(subject)' 가 없다. 크래시 직후이거나 아직 기동되지 않았다.",
                    remedy: "DiagnosticReports 크래시 로그를 확인하고, 앱을 다시 실행해 보라."
                ),
                source: id,
                payload: [
                    "verdict": "not-running",
                    "axTrusted": String(axTrusted),
                ]
            )
        }

        let lsui = readLSUIElement(app.bundlePath)
        if lsui {
            return DoctorFinding(
                category: .runtime,
                severity: .ok,
                body: .init(
                    subject: subject,
                    title: "메뉴바 앱 (창 없는 게 정상)",
                    detail: "프로세스 살아 있음 (pid \(app.pid)). Info.plist LSUIElement=true — 독/메인 창이 없는 메뉴바 앱이다."
                ),
                source: id,
                payload: [
                    "verdict": "menubar",
                    "pid": String(app.pid),
                    "lsuiElement": "true",
                    "axTrusted": String(axTrusted),
                ]
            )
        }

        // layer 0 = normal app windows (status item / dock chrome 제외)
        let owned = windows.filter { $0.ownerPID == app.pid && $0.layer == 0 }
        if !owned.isEmpty {
            return DoctorFinding(
                category: .runtime,
                severity: .ok,
                body: .init(
                    subject: subject,
                    title: "정상",
                    detail: "프로세스 살아 있음 (pid \(app.pid)), CGWindowList 창 \(owned.count)개. 접근성 권한 없이 확인됨."
                ),
                source: id,
                payload: [
                    "verdict": "visible",
                    "pid": String(app.pid),
                    "windowCount": String(owned.count),
                    "lsuiElement": "false",
                    "axTrusted": String(axTrusted),
                ]
            )
        }

        if axTrusted {
            return DoctorFinding(
                category: .runtime,
                severity: .fail,
                body: .init(
                    subject: subject,
                    title: "창이 안 뜬다 — 앱 버그",
                    detail: "프로세스 살아 있음 (pid \(app.pid)) 인데 CGWindowList 에 일반 창이 없다. 접근성 권한은 있어 '못 보는 것'이 아니라 실제로 창이 없다.",
                    remedy: "Main 창 생성·dual-entry 가드·활성화 정책(activationPolicy)을 점검하고, 최근 ship 회귀를 의심하라."
                ),
                source: id,
                payload: [
                    "verdict": "no-window",
                    "pid": String(app.pid),
                    "windowCount": "0",
                    "lsuiElement": "false",
                    "axTrusted": "true",
                ]
            )
        }

        return DoctorFinding(
            category: .runtime,
            severity: .warn,
            body: .init(
                subject: subject,
                title: "판정 불가 — 접근성 권한 필요",
                detail: "프로세스 살아 있음 (pid \(app.pid)), CGWindowList 창 0개. 이 진단기 자체에 접근성 권한이 없어 최종 판정을 보류한다.",
                remedy: "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서 App Launch Doctor 를 허용한 뒤 다시 진단하라."
            ),
            source: id,
            payload: [
                "verdict": "needs-ax",
                "pid": String(app.pid),
                "windowCount": "0",
                "lsuiElement": "false",
                "axTrusted": "false",
            ]
        )
    }

    // MARK: - Matching

    package static func matches(subject: String, app: WindowVisibilityApp) -> Bool {
        let needle = normalize(subject)
        guard !needle.isEmpty else { return false }
        if normalize(app.name) == needle { return true }
        if normalize(app.name).contains(needle) { return true }
        if needle.contains(normalize(app.name)), !app.name.isEmpty { return true }
        if let path = app.bundlePath {
            let base = (path as NSString).lastPathComponent
            let bare = (base as NSString).deletingPathExtension
            if normalize(bare) == needle { return true }
            if normalize(bare).contains(needle) { return true }
            if normalize(base) == needle || normalize(base) == needle + ".app" { return true }
        }
        return false
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    // MARK: - Live defaults

    public static func defaultListRunning() -> [WindowVisibilityApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            // background agents without UI identity still show up; keep .regular + .accessory
            guard app.activationPolicy != .prohibited else { return nil }
            let name = app.localizedName
                ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? app.executableURL?.lastPathComponent
                ?? "pid-\(app.processIdentifier)"
            return WindowVisibilityApp(
                name: name,
                pid: app.processIdentifier,
                bundlePath: app.bundleURL?.path
            )
        }
    }

    public static func defaultListWindows() -> [WindowVisibilityWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let pid = dict[kCGWindowOwnerPID as String] as? Int32
                    ?? (dict[kCGWindowOwnerPID as String] as? Int).map({ Int32($0) })
            else { return nil }
            let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            return WindowVisibilityWindow(ownerPID: pid, ownerName: owner, layer: layer)
        }
    }

    public static func defaultReadLSUIElement(_ bundlePath: String?) -> Bool {
        guard let bundlePath, !bundlePath.isEmpty else { return false }
        let url = URL(fileURLWithPath: bundlePath)
        guard let info = Bundle(url: url)?.infoDictionary else {
            // Bundle() can fail for some paths; fall back to Info.plist read.
            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            guard
                let data = try? Data(contentsOf: plistURL),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return false }
            return isTruthyLSUIElement(plist["LSUIElement"])
        }
        return isTruthyLSUIElement(info["LSUIElement"])
    }

    public static func isTruthyLSUIElement(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return t == "1" || t == "true" || t == "yes"
        default: return false
        }
    }
}
