import Foundation
import WikiLedgerKit

// 드리밍 — 지정 드리밍 기기에서 하루 한 번(또는 `dream run`) 원장을 정리한다.
// 단계: 적재(`LawArchiveRunner`) → 둘러보기(현행 목차·최근 바뀐 기록) → 재료 모으기(지난 실행 뒤 R2 에 적재된 모든 기기의
// 세션 조각, 그 세션이 찾거나 인용한 전신 객체, 설정한 저장소의 판결·조문 — 읽기만, 정리본 제외) → AI 실행 도구 무인 호출로
// 정리 제안 → 안전 검사(`LawDreamPlanner`) → 묶음 하나로 공포 → 목차 새 판 → 보고 공포 → 동기화 → R2 실행 요약(맨 마지막).
// 근거: docs/business-rules.md "드리밍"·"출처 표시"·"심급제"·"작성자와 모델 기록", docs/security.md agent-law 격리 표
// (드리밍 기기만 `dream run`, `dream resume` 은 사람만), docs/architecture.md "agent-law"(드리밍 실행 R2), 결정 0007.
// 모든 공포는 `LawEnactService`(쓰기 게이트·범위 해석기·후처리) 하나로 한다. 작성자는 `app:agent-wiki`, 모델 칸은 AI 판단의 것.

public enum LawDreamTrigger: String, Codable, Sendable {
    /// `dream run` 을 사람·에이전트가 직접 실행.
    case manual
    /// 예약 실행(LaunchAgent). 24시간·새 세션·정지 조건을 본다.
    case scheduled

    /// 드리밍 예약 틱의 LaunchAgent 라벨(`agent-wiki schedule` 이 등록). launchd 는 작업 환경에 `XPC_SERVICE_NAME` 으로 라벨을 넣는다.
    public static let scheduleLabel = "net.ranode.memo-citation-ledger.law-dream"
    public static let scheduleEnvironmentKey = "XPC_SERVICE_NAME"

    /// 예약 틱은 `dream run --scheduled` 로 부른다(`agent-wiki schedule`). 라벨 환경 변수는 옛 plist 를 위한 보조 판정.
    public static let scheduledFlag = "--scheduled"

    public static func detect(environment: [String: String], scheduledFlag: Bool = false) -> LawDreamTrigger {
        if scheduledFlag { return .scheduled }
        return environment[scheduleEnvironmentKey] == scheduleLabel ? .scheduled : .manual
    }
}

public enum LawDreamError: Error, Equatable, CustomStringConvertible {
    case dreamDeviceUnset
    case notDreamDevice(current: String?, dream: String)
    case storageUnavailable(String)
    case notHuman(String)
    case state(String)

    public var description: String {
        switch self {
        case .dreamDeviceUnset: return "드리밍 기기가 지정되지 않음 — world dream-device <키>"
        case .notDreamDevice(let current, let dream):
            return "드리밍 기기가 아님(이 기기 \(current ?? "미등록"), 드리밍 기기 \(dream)) — dream run 거부"
        case .storageUnavailable(let detail): return "드리밍에 R2 가 필요함: \(detail)"
        case .notHuman(let author): return "dream resume 은 사람(author-kind: human)만 — 작성자 \(author)"
        case .state(let detail): return "드리밍 상태: \(detail)"
        }
    }
}

// MARK: - 결과

public struct LawDreamMaterials: Codable, Sendable, Equatable {
    public var manifests: [String] = []
    public var chunks = 0
    public var redactedChunks = 0
    public var sessions = 0
    public var utterances = 0
    public var predecessors: [String] = []
    public var repositoryFiles: [String] = []
    public var recentRecords = 0
    public var deferredIn = 0
}

public struct LawDreamLedgerOutcome: Codable, Sendable, Equatable {
    public var world: String
    public var ledgerKey: String
    /// 이번 실행에서 AI 를 불러 정리했나.
    public var active: Bool
    public var materials: LawDreamMaterials
    public var applied: [LawDreamApplied] = []
    public var discarded: [LawDreamDiscard] = []
    public var deferred = 0
    public var alerts: [String] = []
    public var migrations = 0
    public var aiError: String?
    public var materialError: String?
    public var contents: String?
    public var report: String?
}

public struct LawDreamArchiveSummary: Codable, Sendable, Equatable {
    public var chunks: Int
    public var utterances: Int
    public var unassigned: [String: Int]
    public var failures: Int
    public var manifests: [String]

    public init(_ outcome: LawArchiveOutcome) {
        chunks = outcome.chunks.count
        utterances = outcome.utterances
        unassigned = outcome.unassigned
        failures = outcome.failures.count
        manifests = outcome.manifests
    }
}

public struct LawDreamOutcome: Codable, Sendable, Equatable {
    public var trigger: LawDreamTrigger
    /// 실행하지 않은 이유(자동 실행 조건 미충족·정지).
    public var skipped: String?
    public var run: String?
    public var batch: String?
    public var archive: LawDreamArchiveSummary?
    public var archiveError: String?
    public var ledgers: [LawDreamLedgerOutcome] = []
    public var sync: [String] = []
    /// 쓴 R2 실행 요약 주소.
    public var summaries: [String] = []
    public var failures: [String] = []

    /// AI 응답 오류·재료 읽기 실패·R2 기록 실패가 없었나.
    public var ok: Bool {
        failures.isEmpty && ledgers.allSatisfy { $0.aiError == nil && $0.materialError == nil }
    }
}

public struct LawDreamAlertEntry: Codable, Sendable, Equatable {
    public var world: String
    public var alert: String
}

public struct LawDreamStatus: Codable, Sendable, Equatable {
    public var dreamDevice: String?
    public var currentDevice: String?
    public var isDreamDevice: Bool
    public var lastRun: String?
    public var lastRunAt: String?
    /// 자동 드리밍이 돌 수 있는 가장 이른 시각(마지막 실행 + 간격). 실행한 적 없으면 다음 예약 실행.
    public var nextDue: String?
    public var paused: Bool
    public var pausedBy: [String]
    public var alerts: [LawDreamAlertEntry]
    public var deferred: Int
    public var runner: String
}

// MARK: - 서비스

public struct LawDreamService: Sendable {
    public let file: BoundLedgerFile
    public let catalog: WorldBindingCatalog
    public let settings: LawDreamSettings
    public let runner: LawAIRunner
    /// R2. 없으면 실행을 거부한다(재료가 R2 에 있다).
    public let objectStore: (any LawObjectStore)?
    public let stateStore: LawDreamStateStore
    /// 드리밍 기기에서 먼저 하는 적재. nil 이면 건너뛴다.
    public let archive: (@Sendable () throws -> LawArchiveOutcome)?
    /// 끝날 때 하는 동기화(git·증거물). 결과 문구를 돌려준다.
    public let finish: (@Sendable () -> [String])?
    public let appVersion: String
    public let clock: LawArchiveClock

    public init(
        file: BoundLedgerFile, catalog: WorldBindingCatalog? = nil, settings: LawDreamSettings? = nil,
        runner: LawAIRunner = .live, objectStore: (any LawObjectStore)?, stateStore: LawDreamStateStore,
        archive: (@Sendable () throws -> LawArchiveOutcome)? = nil, finish: (@Sendable () -> [String])? = nil,
        appVersion: String = LedgerVersion.current, clock: LawArchiveClock = .system
    ) {
        self.file = file
        self.catalog = catalog ?? WorldBindingCatalog(worlds: file.effectiveWorlds)
        self.settings = settings ?? file.dream ?? LawDreamSettings()
        self.runner = runner
        self.objectStore = objectStore
        self.stateStore = stateStore
        self.archive = archive
        self.finish = finish
        self.appVersion = appVersion
        self.clock = clock
    }

    /// 드리밍 대상 원장 — 원장 키가 있고 보관되지 않았고 로컬 루트가 있는 ledger 3 원장. 공유(상위 없음) 원장이 먼저.
    public var targets: [LawLedgerTarget] {
        catalog.worlds.filter { world in
            catalog.isLedgerThree(world.name) && (world.key.map(LedgerKeyFormat.isValid) ?? false)
                && !catalog.isArchived(world.name) && FileManager.default.fileExists(atPath: world.rootPath)
        }
        .sorted { ($0.parent == nil ? 0 : 1, $0.name) < ($1.parent == nil ? 0 : 1, $1.name) }
        .map { LawLedgerTarget(worldName: $0.name, file: file, catalog: catalog) }
    }

    /// 드리밍 기기 판정.
    public func checkDevice() throws {
        guard let dream = file.dreamDevice?.trimmingCharacters(in: .whitespaces), !dream.isEmpty else {
            throw LawDreamError.dreamDeviceUnset
        }
        guard file.currentDevice == dream else { throw LawDreamError.notDreamDevice(current: file.currentDevice, dream: dream) }
    }

    /// 정지 판정(모든 드리밍 원장의 기록).
    public func pause() -> LawDreamPause {
        LawDreamPause.evaluate(targets.map { $0.store.scan() })
    }

    func loadState() throws -> LawDreamState {
        if let state = stateStore.load() { return state }
        if let objectStore,
           let rebuilt = try? LawDreamState.rebuild(store: objectStore, ledgerKeys: targets.compactMap(ledgerKey)) {
            return rebuilt
        }
        return LawDreamState()
    }

    func ledgerKey(_ target: LawLedgerTarget) -> String? { catalog.world(named: target.worldName)?.key }

    func appActor(_ model: LawModelRecord?) -> LawActor {
        LawActor(
            author: LawDreamRecordFormat.appAuthor, kind: .app, device: file.currentDevice,
            runtime: model?.runtime ?? LawRuntime.app.rawValue, model: model?.model, effort: model?.effort,
            app: LawDreamRecordFormat.appSlug, appVersion: appVersion)
    }

    // MARK: - status · resume

    public func status() -> LawDreamStatus {
        let state = stateStore.load() ?? LawDreamState()
        let pause = pause()
        var alerts: [LawDreamAlertEntry] = []
        for target in targets {
            alerts += LawDreamMarks(records: target.store.scan()).openAlerts.map {
                LawDreamAlertEntry(world: target.worldName, alert: $0)
            }
        }
        return LawDreamStatus(
            dreamDevice: file.dreamDevice, currentDevice: file.currentDevice,
            isDreamDevice: file.dreamDevice != nil && file.dreamDevice == file.currentDevice,
            lastRun: state.lastRun, lastRunAt: state.lastRunAt,
            nextDue: state.lastRunDate.map { LawTime.format($0.addingTimeInterval(settings.interval)) },
            paused: pause.isPaused, pausedBy: pause.unacknowledgedRestores, alerts: alerts,
            deferred: state.deferred.count,
            runner: "\(settings.resolvedCLI.rawValue):\(settings.resolvedModel):\(settings.resolvedEffort)")
    }

    /// `dream resume` — 사람만. 확인하지 않은 원상회복 기록을 적은 재개 기록을 공포한다. 정지 상태가 아니면 nil.
    @discardableResult
    public func resume(actor: LawActor, target: LawLedgerTarget) throws -> LawStoredRecord? {
        guard actor.kind == .human else { throw LawDreamError.notHuman(actor.author) }
        let pause = pause()
        guard pause.isPaused else { return nil }
        let body = pause.unacknowledgedRestores.map { LawDreamRecordFormat.restorePrefix + $0 }.joined(separator: "\n") + "\n"
        let draft = LawDraft(
            actor: actor, title: LawDreamRecordFormat.resumeTitle, type: LawRecordType.report.rawValue, body: body)
        return try LawEnactService.enact(draft, target: target, now: clock.now())
    }

    // MARK: - run

    public func run(trigger: LawDreamTrigger) throws -> LawDreamOutcome {
        try checkDevice()
        var state = try loadState()
        var outcome = LawDreamOutcome(trigger: trigger)
        let started = clock.now()

        if trigger == .scheduled {
            let pause = pause()
            if pause.isPaused {
                outcome.skipped = "자동 드리밍 정지 — 드리밍 묶음 원상회복 \(pause.unacknowledgedRestores.map { String($0.prefix(8)) }.joined(separator: ", ")), 사람이 dream resume"
                return outcome
            }
            if let last = state.lastRunDate, started.timeIntervalSince(last) < settings.interval {
                outcome.skipped = "마지막 실행(\(LawTime.format(last))) 뒤 \(Int(settings.interval / 3600))시간이 지나지 않음"
                return outcome
            }
        }
        guard let objectStore else { throw LawDreamError.storageUnavailable("R2 저장소 없음") }

        // 1. 드리밍 기기에서는 적재를 먼저 한다.
        if let archive {
            do {
                outcome.archive = LawDreamArchiveSummary(try archive())
            } catch {
                outcome.archiveError = "\(error)"
            }
        }

        // 2. 지난 실행 뒤 적재된 실행 요약(원장마다).
        let targets = self.targets
        var newManifests: [String: [LawArchiveManifest]] = [:]
        for target in targets {
            guard let key = ledgerKey(target) else { continue }
            do {
                newManifests[target.worldName] = try LawSessionChunks.manifests(store: objectStore, ledgerKey: key)
                    .filter { !state.consumedManifests.contains(Self.manifestKey($0)) }
            } catch {
                outcome.failures.append("\(target.worldName) 적재 요약 읽기 실패: \(error)")
            }
        }
        let newChunks = newManifests.values.joined().reduce(0) { $0 + $1.chunks.count }
        if trigger == .scheduled, newChunks == 0 {
            outcome.skipped = "새로 적재된 세션 없음"
            return outcome
        }

        let runStart = try runStartTime(after: state.lastRun)
        let run = LawArchiveKeys.runVersion(runStart)
        let batch = LedgerID.generate(now: runStart)
        outcome.run = run
        outcome.batch = batch

        // 3~4. 원장마다 정리.
        var recordsByWorld: [String: [LawStoredRecord]] = [:]
        for target in targets { recordsByWorld[target.worldName] = target.store.scan() }
        let request = settings.request(prompt: "")
        let actor = appActor(request.modelRecord)
        var nextDeferred: [LawDreamDeferred] = []
        var consumed: [String] = []
        let targetsByWorld = Dictionary(targets.map { ($0.worldName, $0) }, uniquingKeysWith: { first, _ in first })
        for target in targets {
            guard let key = ledgerKey(target) else { continue }
            let carried = state.deferred.filter { $0.world == target.worldName }.map(\.proposal)
            let manifests = newManifests[target.worldName] ?? []
            let context = LedgerRun(
                target: target, ledgerKey: key, run: run, batch: batch, trigger: trigger, actor: actor,
                manifests: manifests, carried: carried, since: state.lastRunDate, targetsByWorld: targetsByWorld,
                recordsByWorld: recordsByWorld, archive: outcome.archive, archiveError: outcome.archiveError)
            let result = processLedger(context, store: objectStore)
            outcome.ledgers.append(result.outcome)
            outcome.failures += result.failures
            if result.consume { consumed += manifests.map(Self.manifestKey) }
            nextDeferred += result.deferred.map { LawDreamDeferred(world: target.worldName, proposal: $0) }
            for world in Set(result.touched) { recordsByWorld[world] = targetsByWorld[world]?.store.scan() ?? [] }
        }

        // 5. 목차 새 판(원장마다). 이번에 정리한 원장은 이번 경보, 아니면 마지막 보고의 경보.
        let contentsActor = appActor(nil)
        for target in targets {
            let ledgerIndex = outcome.ledgers.firstIndex { $0.world == target.worldName }
            if let ledgerIndex, outcome.ledgers[ledgerIndex].aiError != nil { continue }  // 아무것도 공포하지 않는다
            let records = target.store.scan()
            let alerts = ledgerIndex.flatMap { outcome.ledgers[$0].active ? outcome.ledgers[$0].alerts : nil }
                ?? LawDreamMarks(records: records).openAlerts
            let court = file.court ?? LawCourtSettings()
            let docket = LawCourtDocket(records: records, objectionPeriod: court.objectionPeriod)
            let lines = LawContents.lines(
                records: records, notices: docket.notices(now: clock.now()), alerts: alerts,
                maxLines: settings.resolvedContentsMaxLines, objectionPeriod: court.objectionPeriod)
            do {
                if let stored = try LawContents.publish(lines: lines, target: target, actor: contentsActor, now: clock.now()),
                   let ledgerIndex {
                    outcome.ledgers[ledgerIndex].contents = stored.id
                }
            } catch {
                outcome.failures.append("\(target.worldName) 목차 공포 실패: \(error)")
            }
        }

        // 6. 보고 공포(정리한 원장마다).
        for index in outcome.ledgers.indices where outcome.ledgers[index].active && outcome.ledgers[index].aiError == nil {
            let ledger = outcome.ledgers[index]
            guard let target = targetsByWorld[ledger.world] else { continue }
            let draft = LawDraft(
                actor: actor, title: "\(LawDreamRecordFormat.reportTitlePrefix) \(run) \(ledger.world)",
                type: LawRecordType.report.rawValue, origin: LawOrigin.dream.rawValue,
                body: Self.reportBody(ledger, run: run, batch: batch, trigger: trigger, archive: outcome.archive,
                                      archiveError: outcome.archiveError))
            do {
                outcome.ledgers[index].report = try LawEnactService.enact(draft, target: target, now: clock.now()).id
            } catch {
                outcome.failures.append("\(ledger.world) 보고 공포 실패: \(error)")
            }
        }

        // 상태 — 재료로 읽은 요약은 다시 읽지 않고, 미룬 제안은 다음 실행에서 먼저 본다.
        // 원장마다 처리 결과가 미룬 제안 목록 전체를 돌려준다(AI 오류면 받은 그대로).
        let handled = Set(outcome.ledgers.map(\.world))
        state.lastRun = run
        state.lastRunAt = LawTime.format(runStart)
        for key in consumed where !state.consumedManifests.contains(key) { state.consumedManifests.append(key) }
        state.deferred = state.deferred.filter { !handled.contains($0.world) } + nextDeferred
        do {
            try stateStore.save(state)
        } catch {
            outcome.failures.append("드리밍 상태 저장 실패: \(error.localizedDescription)")
        }

        // 7. 동기화(git·증거물).
        outcome.sync = finish?() ?? []

        // 8. 실행 요약 — 실행 폴더의 맨 마지막 파일.
        let finished = LawArchiveKeys.kstTimestamp(clock.now())
        for ledger in outcome.ledgers {
            let summary = LawDreamSummary(
                kind: "dream", ledgerKey: ledger.ledgerKey, world: ledger.world, device: file.currentDevice ?? "",
                run: run, trigger: trigger.rawValue, startedAt: LawTime.format(runStart), finishedAt: finished,
                batch: batch, runtime: ledger.active ? actor.runtime : nil, model: ledger.active ? actor.model : nil,
                effort: ledger.active ? actor.effort : nil,
                consumedManifests: ledger.aiError == nil && ledger.materialError == nil ? ledger.materials.manifests : [],
                applied: ledger.applied, discarded: ledger.discarded, deferred: ledger.deferred, alerts: ledger.alerts,
                migrations: ledger.migrations, contents: ledger.contents, report: ledger.report,
                aiError: ledger.aiError ?? ledger.materialError, sync: outcome.sync)
            let key = LawDreamKeys.summary(ledgerKey: ledger.ledgerKey, run: run)
            do {
                try objectStore.putImmutable(key: key, data: try Self.encode(summary), contentType: "application/json")
                outcome.summaries.append(key)
            } catch {
                outcome.failures.append("실행 요약 기록 실패 \(key): \(error)")
            }
        }
        return outcome
    }

    static func manifestKey(_ manifest: LawArchiveManifest) -> String {
        LawArchiveKeys.manifest(ledgerKey: manifest.ledgerKey, device: manifest.device, run: manifest.run)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// 실행 시작 시각. 마지막 실행과 같은 초면 다음 초까지 기다린다.
    func runStartTime(after last: String?) throws -> Date {
        var now = clock.now()
        guard let last else { return now }
        var attempts = 0
        while LawArchiveKeys.runVersion(now) <= last {
            attempts += 1
            guard attempts <= 3 else { throw LawDreamError.state("시계가 마지막 실행(\(last))보다 앞섬") }
            let seconds = now.timeIntervalSince1970
            clock.sleep(floor(seconds) + 1 - seconds + 0.001)
            now = clock.now()
        }
        return now
    }

    // MARK: - 원장 하나

    struct LedgerRun {
        let target: LawLedgerTarget
        let ledgerKey: String
        let run: String
        let batch: String
        let trigger: LawDreamTrigger
        let actor: LawActor
        let manifests: [LawArchiveManifest]
        let carried: [LawDreamProposal]
        let since: Date?
        let targetsByWorld: [String: LawLedgerTarget]
        let recordsByWorld: [String: [LawStoredRecord]]
        let archive: LawDreamArchiveSummary?
        let archiveError: String?
    }

    struct LedgerResult {
        var outcome: LawDreamLedgerOutcome
        var failures: [String] = []
        var deferred: [LawDreamProposal] = []
        /// 재료로 읽은 요약을 소비했나(AI·재료 오류면 다음 실행에서 다시 읽는다).
        var consume = false
        /// 기록이 바뀐 원장.
        var touched: [String] = []
    }

    func processLedger(_ run: LedgerRun, store: any LawObjectStore) -> LedgerResult {
        let world = run.target.worldName
        var result = LedgerResult(outcome: LawDreamLedgerOutcome(
            world: world, ledgerKey: run.ledgerKey, active: false, materials: LawDreamMaterials()))
        let index = LawScopeIndex(current: world, catalog: catalog)
        let records = run.recordsByWorld[world] ?? []

        // 재료.
        let gathered: LawDreamMaterialSet
        do {
            gathered = try LawDreamMaterialSet.gather(
                manifests: run.manifests, store: store, index: index, records: records, since: run.since,
                repositories: catalog.parentName(of: world) == nil ? settings.resolvedRepositories : [],
                now: clock.now())
        } catch {
            result.outcome.materialError = "재료 읽기 실패: \(error)"
            result.deferred = run.carried
            return result
        }
        var materials = gathered.summary
        materials.deferredIn = run.carried.count
        result.outcome.materials = materials

        let active = !gathered.utterances.isEmpty || !run.carried.isEmpty || run.trigger == .manual
        guard active else {
            result.deferred = run.carried
            result.consume = true
            return result
        }
        result.outcome.active = true
        writeRunFile(store, run, name: "materials.json", value: materials, into: &result)

        // AI 정리 제안.
        let contentsLines = LawContents.current(in: records).map {
            $0.record.body.split(separator: "\n").map(String.init)
        } ?? LawContents.lines(
            records: records, notices: LawCourtNotices(supreme: [], proposalsInObjection: []), alerts: [],
            maxLines: settings.resolvedContentsMaxLines, objectionPeriod: 0)
        let prompt = LawDreamPrompt.build(
            world: world, contents: contentsLines, materials: gathered, carried: run.carried,
            maxChanges: settings.resolvedMaxChanges)
        let proposals: [LawDreamProposal]
        do {
            let response = try runner.runJSON(settings.request(prompt: prompt), as: LawDreamResponse.self)
            guard let list = response.proposals else { throw LawAIRunnerError.invalidJSON("proposals 배열이 없음") }
            proposals = list
        } catch {
            result.outcome.aiError = "\(error)"
            result.deferred = run.carried
            writeRunFile(store, run, name: "decisions.json", value: ["aiError": "\(error)"], into: &result)
            return result
        }

        // 안전 검사.
        let planner = LawDreamPlanner(
            world: world, index: index, foundPredecessors: Set(gathered.predecessors.map(\.id)),
            dreamWorlds: Set(run.targetsByWorld.keys), recordsByWorld: run.recordsByWorld,
            maxChanges: settings.resolvedMaxChanges)
        var plan = planner.plan(run.carried + proposals)
        result.outcome.alerts = plan.alerts
        result.outcome.deferred = plan.deferred.count
        result.deferred = plan.deferred
        if plan.repealCount > settings.resolvedMaxRepeals {
            result.outcome.alerts.append(
                "드리밍 묶음의 폐지 \(plan.repealCount)건이 상한 \(settings.resolvedMaxRepeals)건을 넘어 묶음을 적용하지 않음 — 사람이 확인")
            plan.discarded += plan.changes.map {
                LawDreamDiscard(proposal: $0.proposal.label, reason: "폐지 상한 초과로 묶음 미적용")
            }
            plan.changes = []
        }
        result.outcome.discarded = plan.discarded

        // 묶음 하나로 공포.
        for item in plan.changes {
            do {
                let (ids, touched) = try apply(item.change, run: run)
                result.outcome.applied.append(LawDreamApplied(
                    kind: item.change.kind, world: touched, target: Self.target(of: item.change), ids: ids, note: item.note))
                result.touched.append(touched)
                if case .migrate = item.change { result.outcome.migrations += 1 }
            } catch {
                result.outcome.discarded.append(LawDreamDiscard(proposal: item.proposal.label, reason: "공포 거부: \(error)"))
            }
        }
        result.consume = true
        writeRunFile(store, run, name: "decisions.json", value: DecisionsFile(
            proposals: run.carried + proposals, applied: result.outcome.applied, discarded: result.outcome.discarded,
            deferred: plan.deferred, alerts: result.outcome.alerts), into: &result)
        return result
    }

    struct DecisionsFile: Encodable {
        let proposals: [LawDreamProposal]
        let applied: [LawDreamApplied]
        let discarded: [LawDreamDiscard]
        let deferred: [LawDreamProposal]
        let alerts: [String]
    }

    func writeRunFile<T: Encodable>(_ store: any LawObjectStore, _ run: LedgerRun, name: String, value: T, into result: inout LedgerResult) {
        let key = LawDreamKeys.file(ledgerKey: run.ledgerKey, run: run.run, name: name)
        do {
            try store.putImmutable(key: key, data: try Self.encode(value), contentType: "application/json")
        } catch {
            result.failures.append("실행 기록 실패 \(key): \(error)")
        }
    }

    static func target(of change: LawDreamChange) -> String? {
        switch change {
        case .amend(_, let target, _, _, _, _, _), .repeal(_, let target, _), .finding(_, let target, _),
             .propose(_, let target, _, _), .appeal(_, let target, _):
            return target
        case .migrate(_, let predecessor, _, _, _, _): return predecessor
        case .enact: return nil
        }
    }

    /// 변경 하나를 공포한다. (공포한 id 들, 기록이 바뀐 원장)
    func apply(_ change: LawDreamChange, run: LedgerRun) throws -> ([String], String) {
        func target(_ world: String) throws -> LawLedgerTarget {
            guard let target = run.targetsByWorld[world] else { throw LawDreamError.state("드리밍 대상이 아닌 원장: \(world)") }
            return target
        }
        let actor = run.actor
        let dream = LawOrigin.dream.rawValue
        let now = clock.now()
        switch change {
        case .amend(let world, let id, let also, let title, let body, let tags, let cites):
            let ledger = try target(world)
            guard let current = ledger.store.scan().first(where: { $0.id == id })?.record else {
                throw LawDreamError.state("대상 기록 없음: \(id)")
            }
            // 정리본이 되므로 이관 표시(migrated-from)는 일반 인용으로 남긴다.
            var merged = current.cites.map { cite in
                cite.rel == LawRelation.migratedFrom.rawValue ? LawCite(id: cite.id) : cite
            }
            for cite in cites where !merged.contains(cite) { merged.append(cite) }
            let draft = LawDraft(
                actor: actor, title: title ?? current.title, type: current.type ?? LawRecordType.record.rawValue,
                origin: dream, batch: run.batch, tags: tags ?? current.tags, cites: merged, exhibits: current.exhibits,
                amends: id, amendsAlso: also, source: current.source, body: body)
            return ([try LawEnactService.enact(draft, target: ledger, now: now).id], world)
        case .repeal(let world, let id, let reason):
            let ledger = try target(world)
            let current = ledger.store.scan().first { $0.id == id }?.record
            let draft = LawDraft(
                actor: actor, title: "폐지: \(current?.title ?? String(id.prefix(8)))",
                type: current?.type ?? LawRecordType.record.rawValue, origin: dream, batch: run.batch, repeals: id,
                body: reason)
            return ([try LawEnactService.enact(draft, target: ledger, now: now).id], world)
        case .enact(let world, let title, let body, let tags, let cites):
            let draft = LawDraft(
                actor: actor, title: title, type: LawRecordType.record.rawValue, origin: dream, batch: run.batch,
                tags: tags, cites: cites, body: body)
            return ([try LawEnactService.enact(draft, target: try target(world), now: now).id], world)
        case .finding(let world, let id, let body):
            let ledger = try target(world)
            let records = ledger.store.scan()
            let label = records.first { $0.id == id }?.record.title ?? String(id.prefix(8))
            let draft = LawDraft(
                actor: actor, title: "사실인정: \(label)", type: LawRecordType.finding.rawValue, origin: dream,
                batch: run.batch, cites: [LawCite(id: id, rel: LawRelation.finds.rawValue)],
                amends: LawLedgerView(records: records).currentFinding(for: id)?.id, body: body)
            return ([try LawEnactService.enact(draft, target: ledger, now: now).id], world)
        case .migrate(let world, let predecessor, let title, let body, let tags, let head):
            let ledger = try target(world)
            let migrated = try LawEnactService.enact(LawDraft(
                actor: actor, title: title, type: LawRecordType.record.rawValue, origin: LawOrigin.migration.rawValue,
                batch: run.batch, tags: tags, cites: [LawCite(id: predecessor, rel: LawRelation.migratedFrom.rawValue)],
                body: body), target: ledger, now: now)
            let finding = try LawEnactService.enact(LawDraft(
                actor: actor, title: "사실인정: \(title)", type: LawRecordType.finding.rawValue, origin: dream,
                batch: run.batch, cites: [LawCite(id: migrated.id, rel: LawRelation.finds.rawValue)],
                body: head.joined(separator: "\n") + "\n"), target: ledger, now: now)
            return ([migrated.id, finding.id], world)
        case .propose(let world, let id, let scope, let content):
            let service = LawCourtService(target: try target(world), runner: runner, appVersion: appVersion)
            return ([try service.propose(id, scope: scope, content: content, actor: actor, batch: run.batch, now: now).id], world)
        case .appeal(let world, let id, let reason):
            let service = LawCourtService(target: try target(world), runner: runner, appVersion: appVersion)
            return ([try service.appeal(id, reason: reason, actor: actor, batch: run.batch, now: now).id], world)
        }
    }

    // MARK: - 보고 본문

    static func reportBody(
        _ ledger: LawDreamLedgerOutcome, run: String, batch: String, trigger: LawDreamTrigger,
        archive: LawDreamArchiveSummary?, archiveError: String?
    ) -> String {
        let m = ledger.materials
        var lines = [
            LawDreamRecordFormat.batchPrefix + batch, "run: \(run)", "ledger: \(ledger.ledgerKey)", "trigger: \(trigger.rawValue)",
            "", "## 읽은 재료",
            "- 적재 실행 요약 \(m.manifests.count)건, 세션 조각 \(m.chunks)건(가린 조각 \(m.redactedChunks)), 세션 \(m.sessions), 발화 \(m.utterances)",
            "- 전신 객체 \(m.predecessors.count)건" + (m.predecessors.isEmpty ? "" : ": " + m.predecessors.map { String($0.prefix(8)) }.joined(separator: " ")),
            "- 저장소 문서 \(m.repositoryFiles.count)건",
            "- 최근 바뀐 기록 \(m.recentRecords)건, 지난 실행에서 미룬 제안 \(m.deferredIn)건",
            "", "## 적용한 변경 \(ledger.applied.count)건",
        ]
        lines += ledger.applied.map { item in
            let target = item.target.map { " \($0.prefix(8))" } ?? ""
            let note = item.note.map { " (\($0))" } ?? ""
            return "- \(item.kind)\(target) → \(item.ids.map { String($0.prefix(8)) }.joined(separator: " "))\(note)"
        }
        lines += ["", "## 버린 제안 \(ledger.discarded.count)건"]
        lines += ledger.discarded.map { "- \($0.proposal): \(LawContents.oneLine($0.reason))" }
        lines += ["", "## 미룬 제안 \(ledger.deferred)건", "", "## 경보 \(ledger.alerts.count)건"]
        lines += ledger.alerts.map { LawDreamRecordFormat.alertPrefix + LawContents.oneLine($0) }
        lines += ["", "## 이관 \(ledger.migrations)건", "", "## 적재 보고"]
        if let archive {
            let unassigned = archive.unassigned.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            lines.append("- 조각 \(archive.chunks)건, 발화 \(archive.utterances), unassigned \(archive.unassigned.values.reduce(0, +))건"
                + (unassigned.isEmpty ? "" : "(\(unassigned))") + ", 실패 \(archive.failures)건")
        } else {
            lines.append("- 적재 없음" + (archiveError.map { " — 실패: \(LawContents.oneLine($0))" } ?? ""))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 재료

/// 원장 하나의 재료(둘러보기 포함).
public struct LawDreamMaterialSet: Sendable {
    public var utterances: [LawSummonUtterance] = []
    public var predecessors: [LawScopeObject] = []
    public var repositoryFiles: [(path: String, text: String)] = []
    public var recent: [LawStoredRecord] = []
    public var summary = LawDreamMaterials()

    static let recentLimit = 40
    static let repositoryFileLimit = 60
    static let repositoryFileChars = 1500

    /// 재료 모으기. 정리본(`origin: dream`)은 최근 기록 재료에서 뺀다. 가린 조각은 건너뛰고 센다.
    static func gather(
        manifests: [LawArchiveManifest], store: any LawObjectStore, index: LawScopeIndex, records: [LawStoredRecord],
        since: Date?, repositories: [String], now: Date
    ) throws -> LawDreamMaterialSet {
        var set = LawDreamMaterialSet()
        set.summary.manifests = manifests.map(LawDreamService.manifestKey)
        var sessions: Set<String> = []
        for manifest in manifests {
            for chunk in manifest.chunks {
                set.summary.chunks += 1
                let lines: [LawArchivedUtterance]
                do {
                    lines = try LawSessionChunks.read(store: store, key: chunk.key)
                } catch LawObjectStoreError.notFound {
                    set.summary.redactedChunks += 1
                    continue
                }
                sessions.insert("\(manifest.device)/\(chunk.runtime)/\(chunk.session)")
                set.utterances += lines.map {
                    LawSummonUtterance(
                        ledgerKey: manifest.ledgerKey, device: manifest.device, runtime: chunk.runtime,
                        session: chunk.session, index: $0.index, role: $0.role, text: $0.text,
                        at: LawRunTime.kst(manifest.run), chunk: chunk.key)
                }
            }
        }
        set.summary.sessions = sessions.count
        set.summary.utterances = set.utterances.count

        // 세션이 찾거나 인용한 전신 객체 — 발화 속 id(앞 8자 이상)가 범위 안 전신 객체 하나로 풀리는 것.
        var found: [String: LawScopeObject] = [:]
        for utterance in set.utterances {
            for token in Self.idTokens(utterance.text) {
                let matches = index.idMatches(token)
                if matches.count == 1, let object = matches.first, object.isPredecessor { found[object.id] = object }
            }
        }
        set.predecessors = found.values.sorted { $0.id < $1.id }
        set.summary.predecessors = set.predecessors.map(\.id)

        let cutoff = since ?? now.addingTimeInterval(-7 * 86400)
        let kinds = LawRecordType.knowledgeTypes.map(\.rawValue) + [LawRecordType.finding.rawValue]
        set.recent = Array(records.filter {
            $0.record.promulgated > cutoff && $0.record.origin != LawOrigin.dream.rawValue && kinds.contains($0.record.type ?? "")
        }.sorted { $0.record.promulgated > $1.record.promulgated }.prefix(recentLimit))
        set.summary.recentRecords = set.recent.count

        set.repositoryFiles = Self.repositoryFiles(repositories)
        set.summary.repositoryFiles = set.repositoryFiles.map(\.path)
        return set
    }

    /// 발화 속 16진수 토큰(8~64자).
    static func idTokens(_ text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "(?<![0-9a-fA-F])[0-9a-f]{8,64}(?![0-9a-fA-F])") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
    }

    /// 저장소의 판결·조문 — 규칙 문서와 판결 폴더의 `.md`(읽기만, 앞부분).
    static func repositoryFiles(_ roots: [String]) -> [(path: String, text: String)] {
        let fm = FileManager.default
        var files: [(String, String)] = []
        for root in roots {
            let base = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            var candidates = ["docs/business-rules.md", "docs/security.md", "docs/standards.md"]
                .map { base.appendingPathComponent($0) }
            for folder in ["docs/tracking/decisions", "docs/decisions", "decisions"] {
                let dir = base.appendingPathComponent(folder)
                let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
                candidates += names.map { dir.appendingPathComponent($0) }
            }
            for url in candidates where files.count < repositoryFileLimit {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                files.append((url.path, String(text.prefix(repositoryFileChars))))
            }
        }
        return files
    }
}

// MARK: - 프롬프트

public enum LawDreamPrompt {
    static let utteranceChars = 1500
    static let utteranceBudget = 60_000
    static let recordChars = 600
    static let predecessorChars = 2000

    static func build(
        world: String, contents: [String], materials: LawDreamMaterialSet, carried: [LawDreamProposal], maxChanges: Int
    ) -> String {
        var sections: [String] = []
        sections.append("""
        당신은 agent-law 원장 \(world) 의 드리밍(정리) 담당이다. 아래 재료를 읽고 원장을 정리할 제안을 JSON 객체 하나로만 답한다.

        할 수 있는 제안(kind):
        - "amend": 같은 내용의 기록을 합치거나 고친다. target(대상 id 앞 8자), also(함께 합칠 id 들, 생략 가능), title(생략 가능), body(새 본문 전체), tags, cites([{"id":"..","rel":"cites|testifies"}]).
        - "repeal": 틀린 기록을 폐지한다. target, reason.
        - "enact": 세션에서 배운 새 지식을 record 로 공포한다. title, body, tags, cites.
        - "finding": 지식 기록의 사실인정. target, subject(person|agent-self|project|external), certainty(confirmed|probable|possible), domain(agent-memory-ssot|agent-orchestration|infra-hosting|secrets-identity|gujo-commerce|macos-apps|media-ai-pipeline|dev-workflow), reason, from, until.
        - "migrate": 재료 세션에서 찾거나 인용한 전신 객체를 새 형식으로 옮긴다. target(전신 객체 id), title, body(생략하면 원문), 그리고 사실인정 칸(subject·certainty·domain·reason) 필수.
        - "alert": 사람에게 알릴 것(저장소 판결·조문과 원장의 어긋남 등). message.

        할 수 없는 것(제안하면 버려지거나 항소심 개정안·이관 신청으로 바뀐다):
        - 저장소의 판결·조문 수정(어긋남은 alert 로만), judgment 의 공포·개정·폐지,
        - speaker: user 기록과 조문(article)의 직접 개정·폐지, 정리본(origin: dream)을 증거(testifies)로 인용, 전신 판결(decision) 이관.
        - 한 번에 최대 \(maxChanges)건(넘는 것은 다음 실행), 폐지는 3건 이하로.

        응답 형식:
        {"proposals":[{"kind":"amend","target":"1a2b3c4d","body":"...","title":"..."}, {"kind":"alert","message":"..."}]}
        제안이 없으면 {"proposals":[]}.
        """)
        sections.append("## 현행 목차\n" + (contents.isEmpty ? "(없음)" : contents.joined(separator: "\n")))
        if !carried.isEmpty, let data = try? JSONEncoder().encode(carried), let json = String(data: data, encoding: .utf8) {
            sections.append("## 지난 실행에서 미룬 제안(먼저 다시 검사된다 — 같은 제안을 반복하지 말 것)\n\(json)")
        }
        sections.append("## 최근 바뀐 기록\n" + (materials.recent.isEmpty ? "(없음)" : materials.recent.map { stored in
            let r = stored.record
            return "### \(stored.id.prefix(8)) [\(r.type ?? "")] \(r.title ?? "") (speaker \(r.speaker ?? "-"), origin \(r.origin ?? "-"))\n\(String(r.body.prefix(recordChars)))"
        }.joined(separator: "\n")))
        var budget = utteranceBudget
        var lines: [String] = []
        for utterance in materials.utterances {
            guard budget > 0 else {
                lines.append("…(재료가 길어 이하 생략)")
                break
            }
            let text = String(utterance.text.prefix(min(utteranceChars, budget)))
            budget -= text.count
            lines.append("[\(utterance.device)/\(utterance.runtime)/\(utterance.session) #\(utterance.index) \(utterance.role)] \(text)")
        }
        sections.append("## 새 세션 발화\n" + (lines.isEmpty ? "(없음)" : lines.joined(separator: "\n")))
        sections.append("## 세션이 찾거나 인용한 전신 객체\n" + (materials.predecessors.isEmpty ? "(없음)" : materials.predecessors.map { item in
            "### \(item.id.prefix(8)) [전신 \(item.world) \(item.object.effectiveType ?? "")] \(item.object.title ?? "")\n\(String(item.object.body.prefix(predecessorChars)))"
        }.joined(separator: "\n")))
        if !materials.repositoryFiles.isEmpty {
            sections.append("## 저장소의 판결·조문(읽기만 — 어긋나면 alert)\n" + materials.repositoryFiles.map {
                "### \($0.path)\n\($0.text)"
            }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}
