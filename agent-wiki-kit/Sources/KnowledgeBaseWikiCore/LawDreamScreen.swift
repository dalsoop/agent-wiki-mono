import Foundation
import WikiLedgerKit

// 드리밍 화면 표시 모델 — 저장하지 않는 보기.
// 상태: 드리밍 기기, 마지막 실행(원장의 가장 최근 드리밍 보고 공포일), 다음 예정(그 시각 + 설정 간격), 정지 여부(`LawDreamPause`,
// 원장 기반), 드리밍 AI 설정, R2 엔드포인트 설정 여부. 드리밍 기기의 로컬 상태 파일(`LawDreamStateStore`)에 의존하지 않는다 —
// 원장은 git 으로 모든 기기에 퍼지므로 어느 기기에서나 같은 상태를 본다.
// 실행 이력: 보고마다 묶음 id·적용한 변경 수·버린 제안 수와 이유·경보·이관 수(`LawDreamReportSummary.parse`).
// 묶음 기록: 그 묶음이 바꾼 기록(신규·개정·폐지, 원장별).
// 근거: docs/business-rules.md "드리밍"(안전장치·보고), "공포·개정·폐지·원상회복"(드리밍 묶음 되돌리기).

/// 드리밍에 없는 설정과 그 안내.
public enum LawDreamSetupGap: String, CaseIterable, Sendable, Equatable {
    case dreamDevice
    case ai
    case storageEndpoint

    public var guidance: String {
        switch self {
        case .dreamDevice: return Self.dreamDeviceGuidance
        case .ai: return LawDreamSettings.missingAIGuidance
        case .storageEndpoint: return LawStorageSettings.missingEndpointGuidance
        }
    }

    public static let dreamDeviceGuidance = "드리밍 기기 미지정 — `agent-wiki world dream-device <기기 키>`"
}

/// 실행 이력 한 줄 — 드리밍 보고 하나.
public struct LawDreamRunEntry: Sendable, Equatable, Identifiable {
    public let reportID: String
    public let world: String
    public let promulgated: Date
    public let summary: LawDreamReportSummary

    public var id: String { reportID }
    public var batch: String? { summary.batch }
}

/// 묶음이 바꾼 기록 하나.
public struct LawBatchChange: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case enacted
        case amended(target: String)
        case repealed(target: String)
    }

    public let world: String
    public let record: LawStoredRecord
    public let kind: Kind

    public var id: String { record.id }
}

public struct LawDreamScreen: Sendable {
    public let dreamDevice: String?
    public let currentDevice: String?
    public let isDreamDevice: Bool
    /// 가장 최근 드리밍 보고의 공포일(모든 드리밍 원장).
    public let lastRunAt: Date?
    /// 마지막 실행 + 설정 간격. 실행한 적이 없으면 nil.
    public let nextDueAt: Date?
    public let interval: TimeInterval
    public let paused: Bool
    public let pausedBy: [String]
    /// 설정한 드리밍 AI(`<도구>:<모델>[:<강도>]`), 없으면 nil.
    public let aiLabel: String?
    public let endpointConfigured: Bool
    /// 없는 설정(안내 포함).
    public let gaps: [LawDreamSetupGap]
    /// 실행 이력(새것 먼저).
    public let runs: [LawDreamRunEntry]
    /// 드리밍 원장 이름(공유 원장 먼저).
    public let ledgers: [String]
    /// 되돌리기·재개를 막는 쓰기 게이트 거부 이유(원장마다). 비면 쓸 수 있다.
    public let writeDenials: [String]

    public var canWrite: Bool { writeDenials.isEmpty }

    /// 기록과 설정에서 만든다(파일을 읽지 않는다).
    public static func make(
        file: BoundLedgerFile, ledgers: [(world: String, records: [LawStoredRecord])], writeDenials: [String]
    ) -> LawDreamScreen {
        let settings = file.dream ?? LawDreamSettings()
        var runs: [LawDreamRunEntry] = []
        for ledger in ledgers {
            for report in LawDreamMarks(records: ledger.records).reports {
                runs.append(LawDreamRunEntry(
                    reportID: report.id, world: ledger.world, promulgated: report.record.promulgated,
                    summary: LawDreamReportSummary.parse(report.record.body)))
            }
        }
        runs.sort { ($0.promulgated, $0.reportID) > ($1.promulgated, $1.reportID) }
        let last = runs.first?.promulgated
        let pause = LawDreamPause.evaluate(ledgers.map(\.records))
        let dreamDevice = file.dreamDevice?.trimmingCharacters(in: .whitespaces)
        let storage = file.lawStorage ?? LawStorageSettings()
        var gaps: [LawDreamSetupGap] = []
        if dreamDevice?.isEmpty ?? true { gaps.append(.dreamDevice) }
        if settings.ai == nil { gaps.append(.ai) }
        if storage.resolvedEndpoint == nil { gaps.append(.storageEndpoint) }
        return LawDreamScreen(
            dreamDevice: dreamDevice?.isEmpty == false ? dreamDevice : nil, currentDevice: file.currentDevice,
            isDreamDevice: dreamDevice?.isEmpty == false && dreamDevice == file.currentDevice,
            lastRunAt: last, nextDueAt: last.map { $0.addingTimeInterval(settings.interval) },
            interval: settings.interval, paused: pause.isPaused, pausedBy: pause.unacknowledgedRestores,
            aiLabel: settings.runnerLabel, endpointConfigured: storage.resolvedEndpoint != nil, gaps: gaps, runs: runs,
            ledgers: ledgers.map(\.world), writeDenials: writeDenials)
    }

    /// 드리밍 원장들(`LawDreamService.targets`)을 읽어 만든다. 화면은 배경에서 부른다.
    public static func load(file: BoundLedgerFile, catalog: WorldBindingCatalog) -> LawDreamScreen {
        let targets = LawDreamService.targets(file: file, catalog: catalog)
        return make(
            file: file, ledgers: targets.map { ($0.worldName, $0.store.scan()) },
            writeDenials: targets.compactMap { $0.writeDenial()?.message })
    }
}

public enum LawDreamBatchChanges {
    /// 묶음 `batch` 가 바꾼 기록(원장 순서, 원장 안은 공포 순).
    public static func of(batch: String, ledgers: [(world: String, records: [LawStoredRecord])]) -> [LawBatchChange] {
        ledgers.flatMap { ledger in
            ledger.records.filter { $0.record.batch == batch }.map { stored in
                let kind: LawBatchChange.Kind
                if let target = stored.record.repeals {
                    kind = .repealed(target: target)
                } else if let target = stored.record.amends {
                    kind = .amended(target: target)
                } else {
                    kind = .enacted
                }
                return LawBatchChange(world: ledger.world, record: stored, kind: kind)
            }
        }
    }

    public static func load(batch: String, file: BoundLedgerFile, catalog: WorldBindingCatalog) -> [LawBatchChange] {
        of(batch: batch, ledgers: LawDreamService.targets(file: file, catalog: catalog).map { ($0.worldName, $0.store.scan()) })
    }
}

extension LawDreamScreen {
    /// 화면의 재개 — 사람 작성자(`LedgerHumanEdit.humanActor`)로 `LawDreamService.resume` 을 부른다.
    /// 재개 기록은 `target`(보통 지금 연 원장)에 공포한다. 정지 상태가 아니면 nil.
    @discardableResult
    public static func resume(
        file: BoundLedgerFile, catalog: WorldBindingCatalog, target: LawLedgerTarget,
        author: String = LedgerHumanEdit.humanAuthor(), now: Date = Date()
    ) throws -> LawStoredRecord? {
        let service = LawDreamService(
            file: file, catalog: catalog, objectStore: nil,
            stateStore: LawDreamStateStore(directory: LawDreamStateStore.standardDirectory),
            clock: LawArchiveClock(now: { now }, sleep: { _ in }))
        return try service.resume(actor: LedgerHumanEdit.humanActor(author: author, device: file.currentDevice), target: target)
    }
}
