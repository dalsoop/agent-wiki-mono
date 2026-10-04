import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import SwiftUI

extension LedgerModel {
    var pickerRepositories: [WorldPickerItem] { worldPickerItems.filter { $0.group == .repositories } }
    var pickerSharedWorlds: [WorldPickerItem] { worldPickerItems.filter { $0.group == .shared } }
    var pickerPersonalWorlds: [WorldPickerItem] { worldPickerItems.filter { $0.group == .personal } }
    var pickerOtherWorlds: [WorldPickerItem] { worldPickerItems.filter { $0.group == .other } }

    var currentWorldPickerItem: WorldPickerItem? {
        worldPickerItems.first { $0.world.name == currentWorldName }
    }

    var promotionCandidates: [LedgerObject] {
        guard let store else { return [] }
        let promoted = Set(promotionReceipts.map(\.sourceObjectId))
        return store.heads(objects).filter {
            $0.tags.contains("promotion-candidate")
                && $0.effectiveType != "promotion-receipt"
                && !promoted.contains($0.id)
        }
        .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    }

    var promotionReceipts: [PromotionReceipt] {
        objects.compactMap { object in
            guard object.effectiveType == "promotion-receipt" else { return nil }
            return PromotionReceipt.decode(body: object.body)
        }
        .sorted { $0.promotedAt > $1.promotedAt }
    }

    var gujoWorld: LedgerWorld? {
        worlds.first { item in
            item.name.lowercased() == "gujo-wiki"
                || URL(fileURLWithPath: item.rootPath).standardizedFileURL.path
                    == StateRootKit.url("gujo-wiki").standardizedFileURL.path
        }
    }

    func selectDestination(_ newValue: RepositoryDestination) {
        destination = newValue
        switch newValue {
        case .overview, .tasks, .promotion, .administration: break
        case .knowledge:
            if ![.myNotes, .evidence, .wiki, .graph, .changes, .discuss,
                 .learning, .triage, .review, .trash].contains(area) { area = .wiki }
        case .contributors:
            if ![.agents, .activity, .events].contains(area) { area = .agents }
        case .lawRecords:
            closeLawRecord()  // 메뉴로 들어오면 목록부터
        case .lawContents, .lawCourt, .lawDream, .lawCredibility: break
        }
        publishState()
    }

    func syncDestination(for area: LedgerArea) {
        // ledger 3 원장의 메뉴에는 옛 영역(area)이 없다 — 영역이 바뀌어도 목적지를 옛 메뉴로 옮기지 않는다.
        guard law.kind?.usesLawScreens != true else { return }
        switch area {
        case .agents, .activity, .events: destination = .contributors
        // 구조는 관리 소속이다. 여기 빠져 있으면 area 를 .structure 로 바꾸는 순간
        // 지식으로 튕겨 나가 화면이 안 보인다.
        case .settings, .structure: destination = .administration
        default: destination = .knowledge
        }
    }

    /// 저장소 개요·world 고르기 표시를 배경에서 다시 만든다(fleet 진단·git 살피기는 메인 밖).
    /// ledger 3 원장은 저장소 위키가 아니므로 저장소로 살피지 않는다(`LedgerBackgroundReader.repository`).
    func refreshRepositoryPresentation() {
        let (worlds, rootURL, worldName) = (worlds, rootURL, currentWorldName)
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = LedgerBackgroundReader.repository(worlds: worlds, rootURL: rootURL, worldName: worldName)
            await self?.applyRepositoryPresentation(snapshot, rootURL: rootURL)
        }
    }

    private func applyRepositoryPresentation(_ snapshot: LedgerRepositorySnapshot, rootURL: URL?) {
        worldPickerItems = snapshot.pickerItems
        guard rootURL == self.rootURL else { return }  // 그 사이 다른 원장을 열었다
        repositoryIdentity = snapshot.identity
        repositorySummary = snapshot.summary
        if let summary = snapshot.summary { integrityProblemCount = summary.integrity.issues.count }
    }

    /// repo world 는 `repositoryIdentity` 로 승격하고, repo 가 아닌 world(개인·실험 등)는
    /// 현재 world 이름을 출처로 건넨다 — "저장소가 아니면 승격 불가" 게이트를 없애되,
    /// 어디서 왔는지는 여전히 명시해야 한다(둘 다 없으면 preview 가 거부한다).
    private var promotionSourceWorldName: String? {
        repositoryIdentity == nil ? currentWorldName : nil
    }

    func previewPromotion(objectID: String) {
        promotionPreview = nil
        promotionResult = nil
        guard let source = objects.first(where: { $0.id == objectID }),
              let sourceStore = store,
              let target = gujoWorld else {
            promotionMessage = "승격할 객체와 공유 gujo wiki를 모두 선택할 수 있어야 합니다."
            promotionMessageIsError = true
            return
        }
        do {
            promotionPreview = try PromotionService.preview(
                sourceStore: sourceStore,
                source: source, repository: repositoryIdentity,
                sourceWorldName: promotionSourceWorldName,
                targetWorld: target, promotedBy: "human")
            promotionResult = nil
            promotionMessage = "미리보기 완료 — 출처와 대상이 맞는지 확인한 뒤 승격하세요."
            promotionMessageIsError = false
        } catch {
            promotionMessage = "승격 미리보기 실패: \(error)"
            promotionMessageIsError = true
        }
        publishState()
    }

    func publishPromotion() {
        guard let preview = promotionPreview,
              let source = objects.first(where: { $0.id == preview.sourceObjectId }),
              let sourceStore = store,
              let target = gujoWorld else {
            promotionMessage = "먼저 승격 후보를 미리보기 하세요."
            promotionMessageIsError = true
            return
        }
        do {
            let targetStore = LedgerStore(root: URL(fileURLWithPath: target.rootPath))
            promotionResult = try PromotionService.publish(
                sourceStore: sourceStore,
                targetStore: targetStore,
                source: source,
                repository: repositoryIdentity,
                sourceWorldName: promotionSourceWorldName,
                targetWorld: target,
                promotedBy: "human",
                confirmationToken: preview.confirmationToken,
                targetGate: PromotionTargetGate.standard())
            promotionMessage = promotionResult?.deduplicated == true
                ? "이미 승격된 지식입니다. 기존 영수증을 확인했습니다."
                : "gujo wiki 승격과 양방향 영수증 발행을 완료했습니다."
            promotionMessageIsError = false
            refresh()
        } catch {
            promotionMessage = "승격 발행 실패: \(error)"
            promotionMessageIsError = true
        }
        publishState()
    }

    private var repositoryTaskService: RepositoryTaskService? {
        guard let store else { return nil }
        return RepositoryTaskService(store: store, repository: repositoryIdentity, author: "human")
    }

    func createRepositoryTask(title: String, body: String) -> Bool {
        guard let service = repositoryTaskService else { return repositoryActionFailed("저장소 world가 아닙니다") }
        do {
            let task = try service.createTask(title: title, body: body)
            repositoryActionSucceeded("작업을 만들었습니다: \(task.id.prefix(8))")
            refresh()
            return true
        } catch { return repositoryActionFailed("작업 생성 실패: \(error)") }
    }

    func handoffRepositoryTask(taskID: String, roleID: String, note: String) -> Bool {
        guard let service = repositoryTaskService else { return repositoryActionFailed("저장소 world가 아닙니다") }
        do {
            _ = try service.handoff(taskID: taskID, assignee: roleID, note: note)
            repositoryActionSucceeded("\(roleID) 역할에 작업을 위임했습니다.")
            refresh()
            return true
        } catch { return repositoryActionFailed("작업 위임 실패: \(error)") }
    }

    func runRepositoryTask(
        taskID: String,
        roleID: String,
        instruction: String,
        knowledgeObjectIDs: [String],
        rules: [String]
    ) -> Bool {
        guard let service = repositoryTaskService,
              let roleStore = repositoryAgentRoleStore,
              (try? roleStore.load(id: roleID)) != nil
        else { return repositoryActionFailed("저장소 담당 역할을 먼저 만드세요.") }
        let installed = Self.installedCLIVersion()
        guard installed == LedgerVersion.current,
              DualEntry.isSafeCLIExecutable(Self.cliPath)
        else { return repositoryActionFailed("CLI 업데이트가 필요합니다. PATH 연결은 배포(app-build-manager ship <앱>)가 합니다.") }
        let runtimeTaskID = "kbw-" + UUID().uuidString.lowercased()
        let dispatchID = "dispatch-" + UUID().uuidString.lowercased()
        do {
            _ = try service.handoff(taskID: taskID, assignee: roleID, note: instruction)
            _ = try service.bind(
                taskID: taskID,
                runtimeTaskID: runtimeTaskID,
                dispatchID: dispatchID,
                knowledgeObjectIDs: knowledgeObjectIDs,
                rules: rules)
        } catch { return repositoryActionFailed("실행 컨텍스트 준비 실패: \(error)") }

        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let process = Process()
        process.currentDirectoryURL = rootURL.map(RepositoryAgentRoleStore.repositoryRoot(forWorldRoot:))
        process.executableURL = URL(fileURLWithPath: Self.cliPath)
        process.arguments = [
            "agent", "run", roleID,
            "--canonical-task", taskID,
            "--runtime-task", runtimeTaskID,
            "--dispatch", dispatchID,
            instruction,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(StateRootKit.path(".local/bin")):/opt/homebrew/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        repositoryRunningTaskIDs.insert(taskID)
        process.terminationHandler = { proc in
            Task { @MainActor in
                guard let model = LedgerModel.shared else { return }
                model.repositoryRunningTaskIDs.remove(taskID)
                if proc.terminationStatus == 0 {
                    model.repositoryActionSucceeded("작업 실행이 끝났습니다. checker 검증을 진행하세요.")
                } else {
                    model.repositoryActionFailed("에이전트 실행 실패: \(roleID) (코드 \(proc.terminationStatus))")
                }
                model.refresh()
            }
        }
        do {
            try process.run()
            repositoryActionSucceeded("\(roleID) 실행을 시작했습니다.")
            refresh()
            return true
        } catch {
            repositoryRunningTaskIDs.remove(taskID)
            return repositoryActionFailed("에이전트 기동 실패: \(error.localizedDescription)")
        }
    }

    func rejectRepositoryTask(taskID: String, checker: String) -> Bool {
        guard let service = repositoryTaskService else { return repositoryActionFailed("저장소 world가 아닙니다") }
        do {
            _ = try service.verify(taskID: taskID, checker: checker, outcome: .rejected)
            repositoryActionSucceeded("checker가 작업을 반려했습니다. 수정 실행이 필요합니다.")
            refresh()
            return true
        } catch { return repositoryActionFailed("반려 기록 실패: \(error)") }
    }

    func verifyAndCompleteRepositoryTask(taskID: String, checker: String, result: String) -> Bool {
        guard let service = repositoryTaskService else { return repositoryActionFailed("저장소 world가 아닙니다") }
        do {
            let verification = try service.verify(taskID: taskID, checker: checker, outcome: .verified)
            _ = try service.complete(
                taskID: taskID,
                verificationReceiptID: verification.object.id,
                result: result)
            repositoryActionSucceeded("checker 검증과 canonical task 완료를 기록했습니다.")
            refresh()
            return true
        } catch { return repositoryActionFailed("검증·완료 실패: \(error)") }
    }

    func publishRepositoryKnowledgeCandidate(taskID: String, title: String, body: String) -> Bool {
        guard let service = repositoryTaskService else { return repositoryActionFailed("저장소 world가 아닙니다") }
        do {
            let object = try service.publishKnowledgeCandidate(taskID: taskID, title: title, body: body)
            repositoryActionSucceeded("노하우 후보를 발행했습니다: \(object.id.prefix(8))")
            refresh()
            destination = .promotion
            return true
        } catch { return repositoryActionFailed("노하우 후보 발행 실패: \(error)") }
    }

    @discardableResult
    private func repositoryActionFailed(_ message: String) -> Bool {
        repositoryActionMessage = message
        repositoryActionIsError = true
        publishState()
        return false
    }

    private func repositoryActionSucceeded(_ message: String) {
        repositoryActionMessage = message
        repositoryActionIsError = false
        publishState()
    }
}
