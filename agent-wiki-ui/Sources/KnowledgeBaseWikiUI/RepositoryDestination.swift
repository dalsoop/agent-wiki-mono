import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

/// 옆 메뉴의 목적지. ledger 2 원장(옛 형식)은 개요·지식·작업·승격·담당 에이전트·관리,
/// ledger 3 원장은 목차·기록·심급·드리밍·모델 신빙성(`LawScreenMenu`) — 어느 쪽인지는 설정으로 판정한다(`LawLedgerScreenKind`).
enum RepositoryDestination: String, CaseIterable, Identifiable {
    case overview
    case knowledge
    case tasks
    case promotion
    case contributors
    case administration
    case lawContents
    case lawRecords
    case lawCourt
    case lawDream
    case lawCredibility

    var id: String { rawValue }

    /// ledger 2 원장의 메뉴.
    static let legacyMenu: [RepositoryDestination] = [
        .overview, .knowledge, .tasks, .promotion, .contributors, .administration,
    ]

    /// ledger 3 원장의 메뉴(엔진의 메뉴 순서를 그대로).
    static var lawMenu: [RepositoryDestination] { LawScreenMenu.allCases.map(RepositoryDestination.init) }

    /// 열린 원장의 메뉴. 판정 전(nil)이면 옛 메뉴.
    static func menu(for kind: LawLedgerScreenKind?) -> [RepositoryDestination] {
        kind?.usesLawScreens == true ? lawMenu : legacyMenu
    }

    init(_ menu: LawScreenMenu) {
        switch menu {
        case .contents: self = .lawContents
        case .records: self = .lawRecords
        case .court: self = .lawCourt
        case .dream: self = .lawDream
        case .credibility: self = .lawCredibility
        }
    }

    /// ledger 3 원장 화면인가.
    var isLaw: Bool { !Self.legacyMenu.contains(self) }

    /// AX 자동화와 UI 테스트가 행을 안정적으로 찾는 식별자.
    var sidebarAccessibilityIdentifier: String { "destination-\(rawValue)" }

    @MainActor
    var title: String {
        switch self {
        case .overview: String(localized: "nav.overview", defaultValue: "개요")
        case .knowledge: String(localized: "nav.knowledge", defaultValue: "지식")
        case .tasks: String(localized: "nav.tasks", defaultValue: "작업")
        case .promotion: String(localized: "nav.promotion", defaultValue: "승격")
        case .contributors: String(localized: "nav.contributors", defaultValue: "담당 에이전트")
        case .administration: String(localized: "nav.administration", defaultValue: "관리")
        case .lawContents: L(.LawNavContents)
        case .lawRecords: L(.LawNavRecords)
        case .lawCourt: L(.LawNavCourt)
        case .lawDream: L(.LawNavDream)
        case .lawCredibility: L(.LawNavCredibility)
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .knowledge: "books.vertical"
        case .tasks: "checklist"
        case .promotion: "arrow.up.forward.square"
        case .contributors: "person.2.badge.gearshape"
        case .administration: "gearshape.2"
        case .lawContents: "list.bullet.rectangle"
        case .lawRecords: "doc.text.magnifyingglass"
        case .lawCourt: "building.columns"
        case .lawDream: "moon.stars"
        case .lawCredibility: "chart.bar.xaxis"
        }
    }
}

enum WorldPickerGroup: Int, CaseIterable {
    case personal
    case shared
    case repositories
    case other

    var title: String {
        switch self {
        case .personal: WikiWorldLayer.localPerson.groupTitle
        case .shared: WikiWorldLayer.remoteShared.groupTitle
        case .repositories: WikiWorldLayer.repository.groupTitle
        case .other: WikiWorldLayer.other.groupTitle
        }
    }
}

enum WorldHealth: String {
    case healthy
    case attention
    case unavailable

    var label: String {
        switch self {
        case .healthy: "정상"
        case .attention: "확인 필요"
        case .unavailable: "연결 안 됨"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }
}

struct WorldPickerItem: Identifiable, Equatable {
    let world: LedgerWorld
    let group: WorldPickerGroup
    let layer: WikiWorldLayer
    let title: String
    let subtitle: String
    let health: WorldHealth
    let repoId: String?
    let remote: String?
    let worktreeCount: Int
    let issueCount: Int

    var id: String { world.name }
}

enum RepositoryUIPresentation {
    static func pickerItems(
        worlds: [LedgerWorld],
        registry: FleetRegistry,
        doctor: FleetDoctorReport,
        catalog: WorldBindingCatalog,
        fileManager: FileManager = .default
    ) -> [WorldPickerItem] {
        let healthByPath = Dictionary(uniqueKeysWithValues: doctor.worlds.map {
            (URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path, $0)
        })
        let registrations = Dictionary(uniqueKeysWithValues: registry.canonicalRepositories.map {
            ($0.repoId, $0)
        })

        return worlds.map { world in
            let path = URL(fileURLWithPath: (world.rootPath as NSString).expandingTildeInPath)
                .standardizedFileURL.path
            // 원장 형식은 설정으로 판정한다(`LawLedgerScreenKind`).
            let kind = LawLedgerScreenKind(worldName: world.name, catalog: catalog)
            let isLedgerThree = kind.isLedgerThree
            let fleet = isLedgerThree ? nil : registry.worlds.first {
                $0.name == world.name
                    || URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == path
            }
            // ledger 3 원장은 저장소 위키가 아니다 — 폴더가 git 저장소여도 저장소로 살피지 않는다(설정으로 판정).
            let inspected = isLedgerThree
                ? nil : GitRepositoryInspector.inspect(worldRoot: path)
            let repoId = fleet?.repoId ?? inspected?.repoId
            let registration = repoId.flatMap { registrations[$0] }
            // ledger 3 원장의 층은 설정에 기록된 값만 쓴다(이름·경로로 추정하지 않는다). 기록이 없으면 `other`.
            let layer = isLedgerThree ? (kind.recordedLayer ?? .other) : WikiWorldPresentation.layer(of: world)
            let group: WorldPickerGroup
            switch layer {
            case .localPerson: group = .personal
            case .tenant: group = .personal
            case .remoteShared: group = .shared
            case .repository: group = .repositories
            case .other:
                if fleet?.kind == .repo || inspected != nil {
                    group = .repositories
                } else {
                    group = .other
                }
            }

            let matchingIssues = doctor.issues.filter {
                $0.world == world.name || $0.message.contains(path)
            }
            let healthRow = healthByPath[path]
            let exists = healthRow?.exists ?? fileManager.fileExists(atPath: path)
            let hasObjects = healthRow?.hasObjectsDir
                ?? fileManager.fileExists(atPath: URL(fileURLWithPath: path)
                    .appendingPathComponent("objects").path)
            let health: WorldHealth
            if !exists || !hasObjects || matchingIssues.contains(where: { $0.severity == .error }) {
                health = .unavailable
            } else if !matchingIssues.isEmpty {
                health = .attention
            } else {
                health = .healthy
            }
            return WorldPickerItem(
                world: world,
                group: group,
                layer: layer,
                title: WikiWorldPresentation.title(name: world.name, rootPath: world.rootPath, layer: layer),
                subtitle: WikiWorldPresentation.subtitle(name: world.name, rootPath: world.rootPath, layer: layer),
                health: health,
                repoId: repoId,
                remote: registration?.normalizedRemote ?? fleet?.normalizedGitRemote
                    ?? inspected?.normalizedRemote,
                worktreeCount: registration?.worktreePaths.count
                    ?? fleet?.worktreePaths?.count ?? (inspected == nil ? 0 : 1),
                issueCount: matchingIssues.count)
        }
        .sorted {
            if $0.group.rawValue != $1.group.rawValue { return $0.group.rawValue < $1.group.rawValue }
            return $0.world.name.localizedStandardCompare($1.world.name) == .orderedAscending
        }
    }

    static func preferredRepositoryWorldName(
        worlds: [LedgerWorld], registry: FleetRegistry, doctor: FleetDoctorReport, catalog: WorldBindingCatalog
    ) -> String? {
        pickerItems(worlds: worlds, registry: registry, doctor: doctor, catalog: catalog)
            .first { $0.group == .repositories && $0.health != .unavailable }?.world.name
    }
}
