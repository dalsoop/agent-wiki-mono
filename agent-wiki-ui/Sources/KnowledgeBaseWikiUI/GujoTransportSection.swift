import KnowledgeBaseWikiCore
import SwiftUI
import StateRootKit

/// gujo 원장 전송로 화면 — CLI `gujo status|sync|peer` 와 **같은 Core 를 호출**한다.
///
/// 이 화면이 존재하는 이유는 2026-07-29 사고다: 전송로(syncthing)가 몇 주간 죽어 있었는데
/// 어디에도 뒤처짐이 표시되지 않아 아무도 몰랐다. 그래서 여기서는 "동기화 됨" 같은 요약이 아니라
/// **ahead/behind·미커밋·마지막 sync 시각**을 그대로 드러낸다.
@MainActor
struct GujoTransportSection: View {
    let model: LedgerModel

    @State private var status: GujoSync.Status?
    @State private var busy = false
    @State private var message: String?
    @State private var probing = false
    @State private var blobBusy = false
    @State private var blobMessage: String?

    private var sync: GujoSync {
        let config = LedgerConfig.load()
        let path = config.effectiveWorlds.first { $0.name == "gujo-wiki" }?.rootPath
            ?? StateRootKit.path("gujo-wiki")
        return GujoSync(root: URL(fileURLWithPath: path))
    }

    var body: some View {
        Section("gujo 원장 전송로 (git)") {
            if let status {
                if status.isRepository {
                    LabeledContent("HEAD", value: status.head ?? "?")
                    LabeledContent("뒤처짐", value: deltaText(status))
                        .foregroundStyle(status.ahead > 0 || status.behind > 0 ? Color.orange : .primary)
                    LabeledContent("미커밋", value: "\(status.dirty)개")
                        .foregroundStyle(status.dirty > 0 ? Color.orange : .primary)
                    LabeledContent("마지막 sync", value: lastSyncText(status))
                        .foregroundStyle(status.lastSync == nil ? Color.orange : .primary)
                    LabeledContent("blobs 로컬", value: blobsText(status))
                        .foregroundStyle((status.blobsMissing ?? 0) > 0 ? Color.orange : .primary)
                    if status.peers.isEmpty {
                        LabeledContent("피어", value: "없음 — 시드가 죽으면 복구 경로 없음")
                            .foregroundStyle(.orange)
                    } else {
                        ForEach(status.peers, id: \.name) { peer in
                            LabeledContent("피어 \(peer.name)", value: peerDelta(peer))
                        }
                        Text("피어는 pull-only 다 — fetch·merge 만 하고 push 하지 않는다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("상태", value: "git 저장소가 아니다")
                        .foregroundStyle(.red)
                    Text("복구: 원격 git 저장소가 없다(옛 내부 GitLab 2026-09-24 퇴역) — 피어 Mac 에서 가져오거나 백업에서 되살린다.")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else {
                LabeledContent("상태", value: "조회 중…")
            }

            HStack {
                Button("새로고침") { refresh(probe: false) }
                Button(probing ? "확인 중…" : "시드 도달 확인") { refresh(probe: true) }
                    .disabled(probing)
                Button(busy ? "동기화 중…" : "지금 sync") { runSync() }
                    .disabled(busy || status?.isRepository != true)
            }

            // blobs — garage(S3) 왕복. CLI `gujo blob status|pull|push` 와 같은 Core.
            if blobConfigured {
                HStack {
                    Button(blobBusy ? "blob 작업 중…" : "blob 상태 확인") { runBlob(.plan) }
                        .disabled(blobBusy)
                    Button("blob 받기") { runBlob(.pull) }
                        .disabled(blobBusy)
                    Button("blob 올리기") { runBlob(.push) }
                        .disabled(blobBusy)
                }
                if let blobMessage {
                    Text(blobMessage).font(.caption)
                        .foregroundStyle(blobMessage.hasPrefix("실패") ? Color.red : .secondary)
                        .textSelection(.enabled)
                }
            } else {
                LabeledContent("blob 자격", value: "미설정 — garage 왕복 불가")
                    .foregroundStyle(.orange)
                Text("설정: knowledge-base-wiki gujo blob config --access-key <GK…> --secret-key <…>")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let message {
                Text(message).font(.caption)
                    .foregroundStyle(message.hasPrefix("실패") ? Color.red : .secondary)
                    .textSelection(.enabled)
            }
            Text("정본은 GitLab `workspace/contents/gujo-wiki`(seed). 시드가 없어도 피어끼리 계속 돈다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { refresh(probe: false) }
    }

    private var blobConfigured: Bool {
        GujoBlobConfig.load(root: sync.root) != nil
    }

    private func blobsText(_ status: GujoSync.Status) -> String {
        var text = "\(status.blobsLocal)개 · 시드 garage `gujo-wiki-blobs`"
        if let missing = status.blobsMissing {
            text += missing > 0 ? " · 안 받은 것 \(missing)개" : " · 원격과 일치"
        }
        return text
    }

    private enum BlobAction { case plan, pull, push }

    private func runBlob(_ action: BlobAction) {
        guard let config = GujoBlobConfig.load(root: sync.root) else { return }
        blobBusy = true
        blobMessage = nil
        let root = sync.root
        Task.detached {
            let blob = GujoBlobSync(root: root, config: config)
            let text: String
            switch action {
            case .plan:
                switch blob.plan() {
                case .success(let plan):
                    text = "로컬 \(plan.localCount) · garage \(plan.remoteCount) · 받을 것 \(plan.missingLocal.count) · 올릴 것 \(plan.missingRemote.count)"
                case .failure(let error):
                    text = "실패 — \(error.message)"
                }
            case .pull:
                switch blob.pull() {
                case .success(let outcome):
                    text = "받음 \(outcome.transferred.count)개 · 실패 \(outcome.failed.count)개"
                case .failure(let error):
                    text = "실패 — \(error.message)"
                }
            case .push:
                switch blob.push() {
                case .success(let outcome):
                    text = "올림 \(outcome.transferred.count)개 · 실패 \(outcome.failed.count)개"
                case .failure(let error):
                    text = "실패 — \(error.message)"
                }
            }
            await MainActor.run {
                blobBusy = false
                blobMessage = text
                refresh(probe: false)
            }
        }
    }

    private func deltaText(_ status: GujoSync.Status) -> String {
        if status.ahead == 0 && status.behind == 0 { return "일치" }
        var parts: [String] = []
        if status.ahead > 0 { parts.append("우리가 +\(status.ahead) (미발행)") }
        if status.behind > 0 { parts.append("시드가 +\(status.behind) (미수신)") }
        return parts.joined(separator: " · ")
    }

    private func lastSyncText(_ status: GujoSync.Status) -> String {
        guard let last = status.lastSync else { return "기록 없음" }
        let hours = Int(Date().timeIntervalSince(last) / 3600)
        return hours < 1 ? "방금" : "\(hours)시간 전"
    }

    private func peerDelta(_ peer: GujoSync.PeerState) -> String {
        let ahead = peer.aheadOfUs ?? 0
        let behind = peer.behindUs ?? 0
        if ahead == 0 && behind == 0 { return "일치" }
        var parts: [String] = []
        if ahead > 0 { parts.append("피어가 +\(ahead)") }
        if behind > 0 { parts.append("우리가 +\(behind)") }
        return parts.joined(separator: " · ")
    }

    private func refresh(probe: Bool) {
        if probe { probing = true }
        let service = sync
        Task.detached {
            let next = service.status(probeRemote: probe)
            await MainActor.run {
                status = next
                probing = false
                if probe {
                    message = next.remoteReachable ? "시드 도달 OK" : "실패 — 시드(origin)에 닿지 않는다"
                }
            }
        }
    }

    private func runSync() {
        busy = true
        message = nil
        let service = sync
        Task.detached {
            let result = service.sync()
            await MainActor.run {
                busy = false
                switch result {
                case .success(let outcome):
                    message = "sync 완료 — HEAD \(outcome.head ?? "?")"
                        + (outcome.pushed ? ", 시드에 반영" : ", push 실패(로컬은 병합됨)")
                case .failure(let error):
                    message = "실패 — \(error.message)"
                }
                refresh(probe: false)
            }
        }
    }
}
