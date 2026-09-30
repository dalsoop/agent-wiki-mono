import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

enum RepositoryDestination: String, CaseIterable, Identifiable {
    case overview
    case knowledge
    case tasks
    case promotion
    case contributors
    case administration

    var id: String { rawValue }

    /// AX 자동화와 UI 테스트가 행을 안정적으로 찾는 식별자.
    var sidebarAccessibilityIdentifier: String { "destination-\(rawValue)" }

    var title: String {
        switch self {
        case .overview: String(localized: "nav.overview", defaultValue: "개요")
        case .knowledge: String(localized: "nav.knowledge", defaultValue: "지식")
        case .tasks: String(localized: "nav.tasks", defaultValue: "작업")
        case .promotion: String(localized: "nav.promotion", defaultValue: "승격")
        case .contributors: String(localized: "nav.contributors", defaultValue: "담당 에이전트")
        case .administration: String(localized: "nav.administration", defaultValue: "관리")
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
            let fleet = registry.worlds.first {
                $0.name == world.name
                    || URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == path
            }
            let inspected = GitRepositoryInspector.inspect(worldRoot: path)
            let repoId = fleet?.repoId ?? inspected?.repoId
            let registration = repoId.flatMap { registrations[$0] }
            let layer = WikiWorldPresentation.classify(name: world.name, rootPath: world.rootPath)
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
                title: WikiWorldPresentation.title(name: world.name, rootPath: world.rootPath),
                subtitle: WikiWorldPresentation.subtitle(name: world.name, rootPath: world.rootPath),
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
        worlds: [LedgerWorld], registry: FleetRegistry, doctor: FleetDoctorReport
    ) -> String? {
        pickerItems(worlds: worlds, registry: registry, doctor: doctor)
            .first { $0.group == .repositories && $0.health != .unavailable }?.world.name
    }
}
