import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

struct RepositoryTasksView: View {
    @Bindable var model: LedgerModel
    @State private var filter: RepositoryTaskItem.Status? = nil
    @State private var selectedID: String?
    @State private var showNewTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskBody = ""
    @State private var selectedRoleID = ""
    @State private var instruction = ""
    @State private var knowledgeIDsText = ""
    @State private var rulesText = "AGENTS.md를 준수한다.\n지정된 저장소와 작업 범위만 변경한다.\nchecker 검증 전에는 완료 처리하지 않는다."
    @State private var checker = "checker:human"
    @State private var completionResult = ""
    @State private var knowledgeTitle = ""
    @State private var knowledgeBody = ""

    private var items: [RepositoryTaskItem] {
        let all = model.repositorySummary?.tasks.items ?? []
        return filter.map { status in all.filter { $0.status == status } } ?? all
    }

    private var selectedItem: RepositoryTaskItem? {
        guard let selectedID else { return nil }
        return model.repositorySummary?.tasks.items.first { $0.taskId == selectedID }
    }

    private var roles: [LedgerModel.AgentRole] {
        model.agentRoster.filter { $0.mode != "marker" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("저장소 작업").font(.title2.bold())
                    Text(".wiki task · handoff · done 그래프가 유일한 정본입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showNewTask = true
                } label: {
                    Label("새 작업", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.repositorySummary == nil || model.isReadOnlyWorld)
                .accessibilityIdentifier("repository-task-new")
                Picker("상태", selection: $filter) {
                    Text("전체").tag(RepositoryTaskItem.Status?.none)
                    Text("열림").tag(RepositoryTaskItem.Status?.some(.open))
                    Text("위임됨").tag(RepositoryTaskItem.Status?.some(.delegated))
                    Text("완료").tag(RepositoryTaskItem.Status?.some(.completed))
                }.pickerStyle(.segmented).frame(width: 300)
            }
            .padding(20)
            Divider()
            if model.repositorySummary == nil {
                ContentUnavailableView(L(.RepositoryTasksViewEmptyNotRepoTitle), systemImage: "checklist",
                    description: Text(L(.RepositoryTasksViewEmptyNotRepoDesc)))
            } else {
                HSplitView {
                    List(items, selection: $selectedID) { item in
                        taskRow(item).tag(item.taskId)
                    }
                    .overlay { emptyTaskOverlay }
                    .frame(minWidth: 330, idealWidth: 410)

                    selectedTaskPane
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                }
                // HSplitView 는 스스로 안 늘어난다
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("repository-tasks")
        .sheet(isPresented: $showNewTask) { newTaskSheet }
        .onAppear { selectInitialTask() }
        .onChange(of: items.map(\.taskId)) { _, _ in selectInitialTask() }
        .onChange(of: selectedID) { _, _ in loadSelectedTaskDefaults() }
    }

    @ViewBuilder
    private var emptyTaskOverlay: some View {
        if items.isEmpty {
            ContentUnavailableView(L(.RepositoryTasksViewEmptyNoTasksTitle), systemImage: "checkmark.circle",
                description: Text(L(.RepositoryTasksViewEmptyNoTasksDesc)))
        }
    }

    @ViewBuilder
    private var selectedTaskPane: some View {
        if let selectedItem {
            taskDetail(selectedItem)
        } else {
            ContentUnavailableView(L(.RepositoryTasksViewEmptyPickTaskTitle), systemImage: "cursorarrow.click",
                description: Text(L(.RepositoryTasksViewEmptyPickTaskDesc)))
        }
    }

    private func taskRow(_ item: RepositoryTaskItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: taskIcon(item.status))
                .foregroundStyle(taskColor(item.status)).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(1).frame(minWidth: 0)
                HStack(spacing: 6) {
                    Text(String(item.taskId.prefix(10))).font(.caption.monospaced())
                    if let assignee = item.assignee { Text("→ \(assignee)").font(.caption) }
                    Text(gateLabel(item.orchestration.state)).font(.caption2.weight(.semibold))
                        .foregroundStyle(gateColor(item.orchestration.state))
                }.foregroundStyle(.secondary)
            }
            Spacer()
            if model.repositoryRunningTaskIDs.contains(item.taskId) {
                ProgressView().controlSize(.small)
            } else {
                Text(taskLabel(item.status)).font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(taskColor(item.status).opacity(0.13), in: Capsule())
            }
        }
        .padding(.vertical, 5)
        .accessibilityIdentifier("repository-task-\(item.taskId)")
    }

    private func taskDetail(_ item: RepositoryTaskItem) -> some View {
        ScrollView {
            taskDetailStack(item)
        }
    }

    private func taskDetailStack(_ item: RepositoryTaskItem) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.title2.bold())
                        Text(item.taskId).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Label(taskLabel(item.status), systemImage: taskIcon(item.status))
                        .foregroundStyle(taskColor(item.status))
                }
                orchestrationCard(item)
                if item.status != .completed {
                    executionSection(item)
                    verificationSection(item)
                } else {
                    knowledgeCandidateSection(item)
                }
                if let message = model.repositoryActionMessage {
                    Label(message, systemImage: model.repositoryActionIsError
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(model.repositoryActionIsError ? .red : .green)
                        .font(.callout)
                        .accessibilityIdentifier("repository-task-action-result")
                }
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
    }

    private func orchestrationCard(_ item: RepositoryTaskItem) -> some View {
        GroupBox("실행·검증 게이트") {
            VStack(alignment: .leading, spacing: 7) {
                Label(gateLabel(item.orchestration.state), systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(gateColor(item.orchestration.state))
                if let assignee = item.assignee { Text("담당 역할: \(assignee)") }
                if let runtime = item.orchestration.runtimeTaskId {
                    Text("runtime task  \(runtime)").font(.caption.monospaced()).textSelection(.enabled)
                }
                if let dispatch = item.orchestration.dispatchId {
                    Text("dispatch      \(dispatch)").font(.caption.monospaced()).textSelection(.enabled)
                }
                if let workerDone = item.orchestration.workerDoneObjectId {
                    Label("worker_done \(workerDone.prefix(12))", systemImage: "checkmark.circle")
                        .font(.caption.monospaced()).foregroundStyle(.blue)
                }
                if let failure = item.orchestration.workerFailureObjectId {
                    Label("실행 실패 · 재시도 가능 (코드 \(item.orchestration.workerFailureExitCode ?? -1))",
                          systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    Text("failure receipt \(failure.prefix(12))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let message = item.orchestration.workerFailureMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("지식 컨텍스트 \(item.orchestration.knowledgeObjectIds.count)/32 · 규칙 \(item.orchestration.rulesCapsule.count)/8")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(item.orchestration.warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
    }

    private func executionSection(_ item: RepositoryTaskItem) -> some View {
        GroupBox("1. 저장소 담당 역할 위임·실행") {
            VStack(alignment: .leading, spacing: 10) {
                executionBody(item)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
    }

    @ViewBuilder
    private func executionBody(_ item: RepositoryTaskItem) -> some View {
        if roles.isEmpty {
            ContentUnavailableView {
                Label(L(.RepositoryTasksViewEmptyNoRoleTitle), systemImage: "person.badge.plus")
            } description: {
                Text(L(.RepositoryTasksViewEmptyNoRoleDesc))
            } actions: {
                Button(L(.RepositoryTasksViewEmptyNoRoleAction)) { model.selectDestination(.contributors) }
            }
            .frame(maxHeight: 170)
        } else {
            Picker("담당 역할", selection: $selectedRoleID) {
                ForEach(roles) { role in
                    Text("\(role.name) · \(engineDisplayName(role.engine))").tag(role.name)
                }
            }
            TextEditor(text: $instruction)
                .frame(minHeight: 78)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityLabel("작업 지시")
            TextField("지식 객체 ID (쉼표 구분, 선택)", text: $knowledgeIDsText)
                .textFieldStyle(.roundedBorder)
            Text("실행 규칙 — 한 줄당 1개, 최대 8개").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $rulesText)
                .font(.caption.monospaced()).frame(minHeight: 74)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            runButtons(item)
                .disabled(model.isReadOnlyWorld)  // 보관된 원장(전신)에는 쓰지 않는다
        }
    }

    private func runButtons(_ item: RepositoryTaskItem) -> some View {
        HStack {
            Button("위임만 기록") {
                _ = model.handoffRepositoryTask(
                    taskID: item.taskId,
                    roleID: selectedRoleID,
                    note: instruction)
            }
            Button {
                _ = model.runRepositoryTask(
                    taskID: item.taskId,
                    roleID: selectedRoleID,
                    instruction: instruction,
                    knowledgeObjectIDs: parsedKnowledgeIDs,
                    rules: parsedRules)
            } label: {
                Label(runButtonLabel(item.orchestration.state),
                      systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRoleID.isEmpty
                      || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || model.repositoryRunningTaskIDs.contains(item.taskId))
            .accessibilityLabel(runButtonLabel(item.orchestration.state))
            .accessibilityHint(item.orchestration.state == .executionFailed
                ? "새 runtime과 dispatch로 같은 저장소 작업을 다시 실행합니다."
                : "선택한 저장소 담당 역할로 작업을 실행합니다.")
            .accessibilityIdentifier("repository-task-run")
        }
    }

    private func verificationSection(_ item: RepositoryTaskItem) -> some View {
        GroupBox("2. checker 검증·완료") {
            VStack(alignment: .leading, spacing: 10) {
                if item.orchestration.state == .executionFailed {
                    Label("실행이 실패했습니다. 위에서 엔진 상태를 확인하고 같은 작업을 재시도하세요.",
                          systemImage: "arrow.clockwise.circle")
                        .foregroundStyle(.red)
                } else if item.orchestration.workerDoneObjectId == nil {
                    Label("에이전트 worker_done을 기다리는 중입니다. 성공 보고 전에는 검증할 수 없습니다.",
                          systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("checker ID", text: $checker).textFieldStyle(.roundedBorder)
                    TextEditor(text: $completionResult)
                        .frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        .accessibilityLabel("완료 결과")
                    HStack {
                        Button("반려") {
                            _ = model.rejectRepositoryTask(taskID: item.taskId, checker: checker)
                        }.tint(.red)
                        Button("검증 승인 및 완료") {
                            _ = model.verifyAndCompleteRepositoryTask(
                                taskID: item.taskId,
                                checker: checker,
                                result: completionResult)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("repository-task-verify-complete")
                    }
                    .disabled(model.isReadOnlyWorld)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
    }

    private func knowledgeCandidateSection(_ item: RepositoryTaskItem) -> some View {
        GroupBox("3. 저장소 노하우 → 공유 위키 승격 후보") {
            VStack(alignment: .leading, spacing: 10) {
                Text("작업에서 배운 재사용 지식을 먼저 이 저장소 원장에 남깁니다. 발행 후 승격 화면에서 출처 영수증을 확인하고 gujo wiki로 올립니다.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("노하우 제목", text: $knowledgeTitle).textFieldStyle(.roundedBorder)
                TextEditor(text: $knowledgeBody)
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Button {
                    _ = model.publishRepositoryKnowledgeCandidate(
                        taskID: item.taskId,
                        title: knowledgeTitle,
                        body: knowledgeBody)
                } label: {
                    Label("노하우 후보 발행 후 승격 화면 열기", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isReadOnlyWorld)
                .disabled(knowledgeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || knowledgeBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("repository-task-knowledge-candidate")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
    }

    private var newTaskSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새 저장소 작업").font(.title2.bold())
            Text("canonical task가 .wiki 원장에 발행됩니다.").font(.caption).foregroundStyle(.secondary)
            TextField("작업 제목", text: $newTaskTitle).textFieldStyle(.roundedBorder)
            TextEditor(text: $newTaskBody)
                .frame(width: 470, height: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button("취소") { showNewTask = false }
                Button("작업 만들기") {
                    if model.createRepositoryTask(title: newTaskTitle, body: newTaskBody) {
                        newTaskTitle = ""
                        newTaskBody = ""
                        showNewTask = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22)
    }

    private var parsedKnowledgeIDs: [String] {
        knowledgeIDsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var parsedRules: [String] {
        rulesText.split(separator: "\n").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.prefix(8).map { $0 }
    }

    private func selectInitialTask() {
        if selectedID == nil || !items.contains(where: { $0.taskId == selectedID }) {
            selectedID = items.first?.taskId
        }
    }

    private func loadSelectedTaskDefaults() {
        guard let item = selectedItem else { return }
        selectedRoleID = item.assignee.flatMap { assignee in
            roles.first(where: { $0.name == assignee })?.name
        } ?? roles.first?.name ?? ""
        instruction = item.title
        knowledgeIDsText = item.orchestration.knowledgeObjectIds.joined(separator: ", ")
        if !item.orchestration.rulesCapsule.isEmpty {
            rulesText = item.orchestration.rulesCapsule.joined(separator: "\n")
        }
        completionResult = ""
        knowledgeTitle = "\(item.title)에서 얻은 노하우"
        knowledgeBody = ""
    }

}

private func taskIcon(_ status: RepositoryTaskItem.Status) -> String {
    switch status { case .open: "circle"; case .delegated: "arrow.right.circle"; case .completed: "checkmark.circle.fill" }
}
private func taskColor(_ status: RepositoryTaskItem.Status) -> Color {
    switch status { case .open: .orange; case .delegated: .blue; case .completed: .green }
}
private func taskLabel(_ status: RepositoryTaskItem.Status) -> String {
    switch status { case .open: "열림"; case .delegated: "위임됨"; case .completed: "완료" }
}
private func gateLabel(_ state: RepositoryAgentTaskProjection.State) -> String {
    switch state {
    case .unbound: "runtime 미연결"
    case .awaitingWorker: "작업 결과 대기"
    case .executionFailed: "실행 실패 · 재시도 가능"
    case .stale: "지식 갱신 필요"
    case .awaitingVerification: "checker 검증 대기"
    case .verified: "검증 완료"
    }
}
private func gateColor(_ state: RepositoryAgentTaskProjection.State) -> Color {
    switch state {
    case .unbound: .secondary
    case .awaitingWorker: .indigo
    case .executionFailed: .red
    case .stale: .orange
    case .awaitingVerification: .blue
    case .verified: .green
    }
}
private func runButtonLabel(_ state: RepositoryAgentTaskProjection.State) -> String {
    switch state {
    case .stale: "컨텍스트 갱신·재실행"
    case .executionFailed: "에이전트 재시도"
    default: "에이전트 실행"
    }
}
