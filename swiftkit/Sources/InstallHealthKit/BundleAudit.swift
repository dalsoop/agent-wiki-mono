import Foundation

/// 설치된 .app 한 개의 판정 대상 값.
public struct InstalledBundle: Equatable, Sendable {
    public let path: String
    public let bundleID: String
    public let name: String
    /// 이 번들 안에 있는 확장(.appex)·Helper 실행파일 경로들(없으면 빈 배열).
    public let embeddedExtensions: [String]
    /// 떠 있는 프로세스 수.
    public let runningInstances: Int

    public init(
        path: String,
        bundleID: String,
        name: String,
        embeddedExtensions: [String] = [],
        runningInstances: Int = 0
    ) {
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.embeddedExtensions = embeddedExtensions
        self.runningInstances = runningInstances
    }
}

/// 확장·Helper 를 심어야 하는 앱의 기대치(레포 `make-app.sh` 분석 결과에서 나온다).
public struct ExtensionExpectation: Equatable, Sendable {
    public let bundleID: String
    /// 번들 안에 있어야 하는 항목의 사람이 읽는 이름(예: "DiagramQuickLook.appex").
    public let requiredNames: [String]

    public init(bundleID: String, requiredNames: [String]) {
        self.bundleID = bundleID
        self.requiredNames = requiredNames
    }
}

/// cutoff deny-list 앱 이름(CLAUDE.md §2 deny-list 정본). `.app` 제외, 대소문자 무시 매칭.
public let cutoffDenyListAppNames: Set<String> = [
    "Epic Games Launcher",
    "Flowlog",
    "Hermes",
    "Agent Gaya",
    "CardBackup",
    "DnsSwitcher",
    "Live Translate",
    "Mac Performance Monitor",
    "MCP Manager",
    "ProxmoxMonitor",
    "RemoteAccessMac",
    "ScreenshotSwift",
    "Tracelite",
    "VSCode Extension Runaway Monitor",
    "VPNWireGuard",
    "Record Timelabs",
    "MenuFold",
    "WindowSnap",
]

/// 설치된 번들들의 건강 판정 — 중복 bundle id·중복 인스턴스·확장 누락·deny-list 실행.
public struct BundleAudit: Sendable {
    public init() {}

    /// 같은 bundle id 로 .app 이 둘 이상이면 중복(구·신 이름 공존) — 중복 실행의 원인.
    /// 다중 인스턴스가 설계인 앱이라도 번들이 둘인 건 언제나 문제다.
    public func auditDuplicateBundleIDs(_ bundles: [InstalledBundle]) -> [HealthIssue] {
        Dictionary(grouping: bundles, by: \.bundleID)
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { id, group in
                // **경로를 밝힌다.** 이름만 내보내면 같은 이름의 남의 앱과 구분되지 않는다.
                // 실측(2026-08-05): `net.ranode.wireguard` 경고가 "VPNWireGuard.app,
                // WireGuard.app" 으로 떴는데 `/Applications/WireGuard.app` 은 **공식
                // WireGuard**(`com.wireguard.macos`)였고 우리 것은
                // `~/Applications/swift-app-mono-icons/WireGuard.app` 이었다.
                // 이름만 보고 지웠으면 남의 앱을 날린다.
                let paths = group.map(\.path).sorted()
                return HealthIssue(
                    kind: .duplicateBundleID,
                    severity: .warning,
                    subject: id,
                    detail: "같은 bundle id 의 .app 이 \(group.count)개다:\n    "
                        + paths.joined(separator: "\n    "),
                    remedy: "정본이 아닌 **경로**를 지운다 — 이름이 같아도 다른 앱일 수 있으니"
                        + " 지우기 전에 그 경로의 CFBundleIdentifier 를 확인한다.",
                    isAutoFixable: false
                )
            }
    }

    /// 인스턴스가 2개 이상이면 중복 실행. 다중 인스턴스가 설계인 앱은 `multiInstanceByDesign` 으로 면제한다.
    public func auditDuplicateInstances(
        _ bundles: [InstalledBundle],
        multiInstanceByDesign: Set<String> = []
    ) -> [HealthIssue] {
        bundles
            .filter { $0.runningInstances > 1 && !multiInstanceByDesign.contains($0.bundleID) }
            .sorted { $0.bundleID < $1.bundleID }
            .map { b in
                HealthIssue(
                    kind: .duplicateInstance,
                    severity: .error,
                    subject: b.bundleID,
                    detail: "\(b.name) 프로세스가 \(b.runningInstances)개 떠 있다.",
                    remedy: "LaunchAgent 가 직접 exec 하는지 먼저 보고(open -a 로 교정), 앱에 SingleInstanceKit 가드가 있는지 확인한다.",
                    isAutoFixable: false
                )
            }
    }

    /// cutoff deny-list 앱이 실행 중이면 경고. `runningApps` 는 `(localizedName, bundleID)` 쌍.
    public func auditDenyListRunning(
        _ runningApps: [(name: String, bundleID: String)],
        denyList: Set<String> = cutoffDenyListAppNames
    ) -> [HealthIssue] {
        let lowered = Set(denyList.map { $0.lowercased() })
        return runningApps
            .filter { lowered.contains($0.name.lowercased()) }
            .sorted { $0.name < $1.name }
            .map { app in
                HealthIssue(
                    kind: .denyListRunning,
                    severity: .warning,
                    subject: app.bundleID,
                    detail: "\(app.name) 이(가) 실행 중이다 — cutoff deny-list 앱이므로 꺼야 한다.",
                    remedy: "앱을 종료한다. 로그인 항목·Background Items 에서도 제거한다.",
                    isAutoFixable: false
                )
            }
    }

    /// SUFeedURL 이 Info.plist 에 있는데 Sparkle.framework 가 번들에 없으면 고아 피드.
    /// 빌드 스크립트가 게이트 없이 주입했거나, 프레임워크 링크가 빠졌거나.
    public func auditSparkleFeedWithoutFramework(_ bundles: [InstalledBundle]) -> [HealthIssue] {
        bundles.compactMap { bundle -> HealthIssue? in
            let plistPath = "\(bundle.path)/Contents/Info.plist"
            let frameworkPath = "\(bundle.path)/Contents/Frameworks/Sparkle.framework"
            guard FileManager.default.fileExists(atPath: plistPath) else { return nil }
            let feedURL = (NSDictionary(contentsOfFile: plistPath)?["SUFeedURL"] as? String) ?? ""
            guard !feedURL.isEmpty, !FileManager.default.fileExists(atPath: frameworkPath) else { return nil }
            return HealthIssue(
                kind: .sparkleFeedWithoutFramework,
                severity: .warning,
                subject: bundle.bundleID,
                detail: "\(bundle.name) 에 SUFeedURL 이 있지만 Sparkle.framework 가 없다 — 피드가 동작하지 않는다.",
                remedy: "빌드 스크립트의 ensure_sparkle_feed 게이트를 확인하거나 SUFeedURL 을 제거한다.",
                isAutoFixable: false
            )
        }
    }

    /// 확장·Helper 를 심어야 하는 앱인데 설치본에 없으면 문제.
    /// 빌드·실행은 성공해서 안 보이므로(Quick Look·Finder 확장·권한 작업만 죽는다) 반드시 기계로 잡는다.
    public func auditMissingExtensions(
        _ bundles: [InstalledBundle],
        expectations: [ExtensionExpectation]
    ) -> [HealthIssue] {
        let byID = Dictionary(grouping: bundles, by: \.bundleID)
        return expectations.sorted { $0.bundleID < $1.bundleID }.flatMap { want -> [HealthIssue] in
            (byID[want.bundleID] ?? []).compactMap { bundle in
                let present = Set(bundle.embeddedExtensions.map { ($0 as NSString).lastPathComponent })
                let missing = want.requiredNames.filter { !present.contains($0) }
                guard !missing.isEmpty else { return nil }
                return HealthIssue(
                    kind: .missingExtension,
                    severity: .error,
                    subject: want.bundleID,
                    detail: "설치본에 \(missing.joined(separator: ", ")) 이(가) 없다 — 공용 설치 스크립트로 덮이면 확장이 조용히 빠진다.",
                    remedy: "그 앱의 scripts/install-app.sh 로 재설치한다(공용 install-macos-app.sh 는 확장을 안 만든다).",
                    isAutoFixable: false
                )
            }
        }
    }
}
