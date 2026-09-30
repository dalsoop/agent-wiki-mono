import KnowledgeBaseWikiCore
import SwiftUI

extension Notification.Name {
    /// 설정 → 에이전트 연동에서 온보딩 시트를 다시 열 때.
    static let agentWikiShowWelcomeOnboarding = Notification.Name("agentWikiShowWelcomeOnboarding")
}

/// 첫 실행·설정에서 여는 사람용 온보딩.
/// CLI / multi-home 스킬 surface / dual-entry 상태를 보여주고 원클릭 부착.
struct WelcomeOnboardingView: View {
    var onDismiss: () -> Void

    @State private var cli = Onboarding.cliStatus()
    @State private var skill = Onboarding.skillStatus()
    @State private var dual = Onboarding.dualEntryStatus()
    @State private var attachMessage: String?
    @State private var attaching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pitch
                    statusCard
                    attachCard
                    agentHint
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
        .onAppear { refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 28))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Wiki")
                    .font(.title2.bold())
                Text("에이전트가 원장을 조회·발행하고, 사람은 앱으로 봅니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이 앱이 하는 일")
                .font(.headline)
            Label("에이전트는 `agent-wiki` CLI 로 원장 검색·발행", systemImage: "terminal")
            Label("정본 원장 이름은 gujo wiki (`~/gujo-wiki`)", systemImage: "archivebox")
            Label("코딩 에이전트 스킬은 multi-home surface 로 부착", systemImage: "link")
            Label("상세 훅·연동은 설정 → 에이전트 연동", systemImage: "gearshape")
        }
        .font(.callout)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("설치 상태")
                    .font(.headline)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            statusRow(title: "agent-wiki CLI", status: cli)
            statusRow(title: "에이전트 스킬 (surface)", status: skill)
            statusRow(title: "dual-entry (안전 CLI)", status: dual)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func statusRow(title: String, status: OnboardStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.ok ? .green : .orange)
                .accessibilityLabel(status.ok ? "준비됨" : "필요")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(status.ok ? status.detail : (status.hint ?? status.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var attachCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("스킬 부착")
                .font(.headline)
            Text("Codex · Claude · Grok · agents 홈에 agent-wiki 스킬을 붙입니다. 이미 있는 경로는 건너뜁니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                runAttach()
            } label: {
                if attaching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(
                        skill.ok ? "다시 부착 (skill-install)" : "지금 부착 (skill-install)",
                        systemImage: "link.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(attaching)
            .accessibilityIdentifier("welcome-attach-skill")
            if let attachMessage {
                Text(attachMessage)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.08)))
    }

    private var agentHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("에이전트 시작 루틴")
                .font(.headline)
            let lines = [
                "agent-wiki context \"질문\"     # 원장 우선 조회",
                "agent-wiki search 키워드",
                "agent-wiki show <id>",
                "agent-wiki skill-status       # surface 상태",
                "# 발행은 wiki-record 스킬 규약",
            ]
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            Text("제품 Agent Wiki · 스킬 agent-wiki · 호환 별칭 knowledge-base-wiki · memo-citation-ledger")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            Button("나중에") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("시작하기") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome-dismiss")
        }
        .padding(16)
    }

    private func refresh() {
        cli = Onboarding.cliStatus()
        skill = Onboarding.skillStatus()
        dual = Onboarding.dualEntryStatus()
    }

    private func runAttach() {
        attaching = true
        attachMessage = nil
        defer { attaching = false }
        do {
            let r = try Onboarding.attachSkillSurface()
            if r.errors.isEmpty {
                attachMessage = r.attached.isEmpty
                    ? "변경 없음 (이미 부착되었거나 홈 없음)"
                    : "부착 \(r.attached.count) paths"
            } else {
                attachMessage = "부분 실패: \(r.errors.joined(separator: "; "))"
            }
            refresh()
        } catch {
            attachMessage = "실패: \(error.localizedDescription)"
        }
    }
}
