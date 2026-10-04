import KnowledgeBaseWikiCore
import SwiftUI

/// 화면은 그냥 메모앱이다 — 목록/편집/기록. 불변 원장(발행·철회·uuid)은 배관이라 안 보인다.
struct LedgerView: View {
    @Bindable var model: LedgerModel
    @Environment(\.openSettings) private var openSettings
    @State private var showAgentTask = false
    @State private var agentTaskRole = ""
    @State private var agentTaskText = ""
    @State private var showCreateRole = false
    @State private var newRoleID = ""
    @State private var newRoleName = ""
    @State private var newRoleSummary = ""
    @State private var newRoleEngine = "codex"
    @State private var newRoleResponsibilities = ""

    /// content 열이 안내 플레이스홀더뿐인 영역 — 2열(sidebar+detail)로 공간을 준다.
    private var usesTwoColumnLayout: Bool {
        if model.destination.isLaw { return true }  // ledger 3 화면은 옆 메뉴 + 본문 2열
        if ![.knowledge, .contributors].contains(model.destination) { return true }
        switch model.area {
        case .graph, .triage, .review, .settings: return true
        default: return false
        }
    }

    var body: some View {
        if model.rootURL == nil {
            ContentUnavailableView {
                Label(L(.LedgerViewEmptyRootTitle), systemImage: "square.and.pencil")
            } description: {
                Text(L(.LedgerViewEmptyRootDesc))
            } actions: {
                Button(L(.LedgerViewEmptyRootAction)) { model.chooseRoot() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                WorkbenchStrip(model: model)
                DestinationSubnavigationBar(model: model)
                Divider()
                splitView
            }
            .alert("오류", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var splitView: some View {
            Group {
                if usesTwoColumnLayout {
                    // graph / triage / review / settings — 가운데 열이 비므로 2열.
                    NavigationSplitView {
                        areaSidebar
                    } detail: {
                        LedgerDetailPane(
                            model: model,
                            showAgentTask: $showAgentTask,
                            agentTaskRole: $agentTaskRole)
                    }
                } else {
                    NavigationSplitView {
                        areaSidebar
                    } content: {
                        LedgerContentColumn(model: model, showCreateRole: $showCreateRole)
                    } detail: {
                        LedgerDetailPane(
                            model: model,
                            showAgentTask: $showAgentTask,
                            agentTaskRole: $agentTaskRole)
                    }
                }
            }
            .navigationTitle("Agent Wiki")
            .onAppear {
                let next = LedgerAreaOwnership.clampArea(model.area)
                if next != model.area { model.area = next }
            }
            .onChange(of: model.area) { _, newArea in
                let next = LedgerAreaOwnership.clampArea(newArea)
                if next != newArea {
                    model.area = next
                    return
                }
                model.syncDestination(for: newArea)
                if newArea == .settings { openSettings() }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if model.isArchivedWorld {
                        // 보관된 원장(전신) — 읽기 전용. 편집 버튼은 각 화면이 `isReadOnlyWorld` 로 숨긴다(판정 전에도 숨김).
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                            Text(L(.LawNavArchivedBanner)).font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.gray.opacity(0.15))
                        .accessibilityIdentifier("archived-ledger-banner")
                    }
                    if let stale = model.cliStaleVersion {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("CLI 버전 불일치 — 설치본 \(stale), 앱 \(LedgerVersion.current). 앱이 옛 CLI 를 부를 수 있습니다.")
                                .font(.caption)
                            Spacer()
                            staleCLIActions
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.orange.opacity(0.15))
                    }
                }
            }
            .sheet(isPresented: $showAgentTask) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(agentTaskRole) 에게 작업").font(.headline)
                    TextEditor(text: $agentTaskText)
                        .font(.body).frame(width: 420, height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    HStack {
                        Text("백그라운드로 실행 — 진행은 워크벤치, 결과는 발행으로 돌아옵니다.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("취소") { showAgentTask = false }
                        Button("실행") {
                            model.runAgent(role: agentTaskRole, task: agentTaskText)
                            agentTaskText = ""
                            showAgentTask = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(agentTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
            }
            .sheet(isPresented: $showCreateRole) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("저장소 담당 에이전트 역할").font(.title2.bold())
                    Text("엔진 이름이 아니라 이 저장소에서 맡을 책임으로 정의합니다. 정본은 .agents/roles입니다.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("역할 ID (예: release-maintainer)", text: $newRoleID)
                        .textFieldStyle(.roundedBorder)
                    TextField("표시 이름", text: $newRoleName).textFieldStyle(.roundedBorder)
                    TextField("한 줄 설명", text: $newRoleSummary).textFieldStyle(.roundedBorder)
                    Picker("실행 엔진", selection: $newRoleEngine) {
                        ForEach(RepositoryAgentRole.supportedEngines, id: \.self) { engine in
                            Text(engineDisplayName(engine)).tag(engine)
                        }
                    }.pickerStyle(.segmented)
                    Text("담당 범위와 완료 기준").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $newRoleResponsibilities)
                        .frame(width: 520, height: 150)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    HStack {
                        Spacer()
                        Button("취소") { showCreateRole = false }
                        Button("역할 만들기") {
                            createRepositoryRole()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newRoleID.isEmpty || newRoleResponsibilities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("repository-agent-role-create-confirm")
                    }
                }.padding(22)
            }
    }

    @ViewBuilder
    private var staleCLIActions: some View {
        Text(LedgerModel.cliPathGuidance).font(.caption).foregroundStyle(.secondary)
        Button("숨기기") { model.cliStaleVersion = nil }.buttonStyle(.link).font(.caption)
    }

    private func createRepositoryRole() {
        let created = model.createRepositoryAgentRole(
            id: newRoleID,
            displayName: newRoleName,
            summary: newRoleSummary,
            engine: newRoleEngine,
            responsibilities: newRoleResponsibilities)
        guard created else { return }
        showCreateRole = false
        newRoleID = ""
        newRoleName = ""
        newRoleSummary = ""
        newRoleResponsibilities = ""
    }

    @ViewBuilder
    private var worldHealthIcon: some View {
        if let health = model.currentWorldPickerItem?.health {
            Image(systemName: health.systemImage)
                .foregroundStyle(health == .healthy ? .green : .orange)
        }
    }

    private var areaSidebar: some View {
        List(selection: Binding(
            get: { model.destination },
            set: { model.selectDestination($0) }
        )) {
            Section {
                Menu {
                    worldPickerSection(WikiWorldLayer.localPerson.groupTitle, items: model.pickerPersonalWorlds)
                    worldPickerSection(WikiWorldLayer.remoteShared.groupTitle, items: model.pickerSharedWorlds)
                    worldPickerSection(WikiWorldLayer.repository.groupTitle, items: model.pickerRepositories)
                    worldPickerSection(WikiWorldLayer.other.groupTitle, items: model.pickerOtherWorlds)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: model.currentWorldPickerItem?.layer.systemImage
                                  ?? "globe.asia.australia")
                            Text(model.currentWorldPickerItem?.title ?? model.currentWorldName ?? "원장")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            worldHealthIcon
                        }
                        Text(model.currentWorldPickerItem?.subtitle
                             ?? model.currentWorldPickerItem?.group.title
                             ?? "world")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).frame(minWidth: 0)
                    }
                }
            }
            Section(model.law.kind?.usesLawScreens == true ? L(.LawNavSection) : "Repository") {
                ForEach(model.sidebarDestinations) { destination in
                    Button {
                        // List 선택만 믿으면 AX 클라이언트의 행 클릭이 바인딩까지 닿지 않는다.
                        // 명시적으로 같은 선택 경로를 호출해 상태 미러 등의 부수 효과도 보존한다.
                        model.selectDestination(destination)
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                    .buttonStyle(.plain)
                        .tag(destination)
                        .accessibilityLabel(destination.title)
                        .accessibilityIdentifier(destination.sidebarAccessibilityIdentifier)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 205, ideal: 230)
    }

    @ViewBuilder
    private func worldPickerSection(_ title: String, items: [WorldPickerItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Button {
                        model.currentWorldName = item.world.name
                        model.switchWorld(item.world)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(item.title + (item.world.name == model.currentWorldName ? " ✓" : ""))
                                Text(item.world.name).font(.caption.monospaced())
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minWidth: 0)
                            }
                        } icon: {
                            Image(systemName: item.layer.systemImage)
                        }
                    }
                }
            }
        }
    }
}

func relLabel(_ rel: String) -> String {
    switch rel {
    case "supports": return "재현"
    case "contradicts": return "반박"
    case "summarizes": return "요약"
    case "references", "cites": return "참고"
    default: return rel
    }
}
