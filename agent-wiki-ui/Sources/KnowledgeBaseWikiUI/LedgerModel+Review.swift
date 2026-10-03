import CommandKit
import Foundation
import KnowledgeBaseWikiCore

// 심사대 사람 판정 — 정제본(distiller digest)을 루브릭+코멘트로 수락/반려.
// 수락 → 위키 확립(개념 발행). 반려 → 학습 신호(세대 진화 입력).
extension LedgerModel {
    static let establishRel = "establishes"

    /// 이 정제본에 대한 사람 심사 판정(있으면). 최신 것 하나.
    func reviewVerdict(of digest: LedgerDocument) -> ReviewVerdict? {
        let reviews = objects.filter { obj in
            obj.effectiveType == "review"
                && obj.cites.contains { $0.rel == ReviewVerdict.rel && $0.id == digest.head.id }
        }.sorted { ($0.published, $0.id) > ($1.published, $1.id) }
        return reviews.first.flatMap { ReviewVerdict(body: $0.body) }
    }

    /// 심사 가능한 정제본 — digests 로 원문을 인용한 문서(사람·distiller 저작 모두). 사건성·철회 제외.
    /// digestDocuments(human 전용)와 달리 distiller 초안도 포함한다 — 심사대의 진짜 대상.
    var reviewableDigests: [LedgerDocument] {
        allDocuments.filter { doc in
            doc.head.cites.contains { $0.rel == Self.digestRel }
                && !doc.head.isProcess && doc.head.retracts == nil
        }
    }

    /// 심사 대기 정제본 — 아직 사람 판정이 없는 것.
    var pendingReviewDigests: [LedgerDocument] {
        reviewableDigests.filter { reviewVerdict(of: $0) == nil }
    }

    // MARK: - distiller 세대 (카르파시식 경험학습 — 반려 피드백으로 역할이 세대별로 개선되나)

    struct GenerationStat: Identifiable {
        let id: String
        let index: Int
        let startedAt: Date
        var accepted = 0
        var rejected = 0
        var pending = 0
        var total: Int { accepted + rejected + pending }
        /// 수용률 = 수락 / (수락+반려). 판정 없는 세대는 nil.
        var acceptanceRate: Double? {
            accepted + rejected == 0 ? nil : Double(accepted) / Double(accepted + rejected)
        }
    }

    /// distiller 세대별 수용 통계 — role-definition 버전이 세대 경계. 각 정제본을 발행시점의 세대에 귀속.
    func distillerGenerationStats() -> [GenerationStat] {
        let gens = objects
            .filter { $0.effectiveType == "role-definition" && $0.title == "역할정의: distiller" }
            .sorted { $0.published < $1.published }
        let digests = reviewableDigests.filter { $0.head.author == "distiller" }
        var stats: [GenerationStat]
        if gens.isEmpty {
            // 아직 진화 전 — 초기 세대 하나로.
            let start = digests.map(\.head.published).min() ?? Date(timeIntervalSince1970: 0)
            stats = [GenerationStat(id: "gen1", index: 1, startedAt: start)]
        } else {
            stats = gens.enumerated().map { i, g in GenerationStat(id: g.id, index: i + 1, startedAt: g.published) }
        }
        for d in digests {
            let idx = stats.lastIndex { $0.startedAt <= d.head.published } ?? 0
            switch reviewVerdict(of: d)?.decision {
            case .accept: stats[idx].accepted += 1
            case .reject: stats[idx].rejected += 1
            case nil: stats[idx].pending += 1
            }
        }
        return stats
    }

    /// 수락 — 심사 기록 발행 + 위키 개념으로 확립(정제본 본문을 개념 객체로, 원문 계보 인용).
    func acceptDigest(_ digest: LedgerDocument, scores: [String: Int], comment: String) {
        guard let store = legacyWritableStore() else { return }
        let verdict = ReviewVerdict(decision: .accept, scores: scores, comment: comment)
        let title = digest.title.replacingOccurrences(of: "정제: ", with: "")
        do {
            // 심사 기록(학습 신호·이력).
            _ = try store.publish(
                author: "human", title: "심사: 수락 — \(title)", type: "review",
                body: verdict.body(),
                cites: [.init(id: digest.head.id, rel: ReviewVerdict.rel)])
            // 위키 확립 — 사람이 승인한 정제본을 개념 객체로. 정제본을 establishes 로 인용해 계보 유지.
            _ = try store.publish(
                author: "human", title: "개념: \(title)", type: "concept",
                body: digest.head.body,
                cites: [.init(id: digest.head.id, rel: Self.establishRel)])
            refresh()
            errorMessage = nil
        } catch { errorMessage = "확립 실패: \(error.localizedDescription)" }
    }

    /// 반려 — 심사 기록만 발행(코멘트·점수). distiller 세대 진화의 학습 신호가 된다.
    func rejectDigest(_ digest: LedgerDocument, scores: [String: Int], comment: String) {
        guard let store = legacyWritableStore() else { return }
        let verdict = ReviewVerdict(decision: .reject, scores: scores, comment: comment)
        let title = digest.title.replacingOccurrences(of: "정제: ", with: "")
        do {
            _ = try store.publish(
                author: "human", title: "심사: 반려 — \(title)", type: "review",
                body: verdict.body(),
                cites: [.init(id: digest.head.id, rel: ReviewVerdict.rel)])
            refresh()
            errorMessage = nil
        } catch { errorMessage = "반려 발행 실패: \(error.localizedDescription)" }
    }

    /// distiller 세대 진화 — 반려 피드백으로 역할을 다음 세대로 개정(CLI agent evolve, 백그라운드).
    /// claude 를 스폰하는 장시간 작업이라 상태만 표시하고 완료 시 새로고침.
    func evolveDistiller() {
        let cli = Self.cliPath
        errorMessage = "distiller 세대 진화 중… (반려 피드백 반영, 수 분)"
        Task.detached { [weak self] in
            let runner = ProcessCommandRunner()
            let result = await runner.run(cli, ["agent", "evolve", "distiller"], timeout: 2100)
            let ok = result.ok
            let out = result.stdout + result.stderr
            await MainActor.run {
                self?.errorMessage = ok ? nil : "세대 진화 실패: \(out.suffix(160))"
                self?.refresh()
            }
        }
    }

    /// 붙여넣기 원문 수집(인app) — blob 봉인 + paste 근거로 수집함. CLI capture --text 와 같은 결과.
    func captureText(title: String, project: String?, body: String) {
        guard let store = legacyWritableStore() else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "원문이 비어 있습니다"; return }
        do {
            let sha = try BlobStore(root: store.root).put(Data(trimmed.utf8))
            let prov = Provenance(kind: "text", project: project?.isEmpty == true ? nil : project, blob: sha)
            _ = try store.publish(
                author: "human", title: "근거: \(title.isEmpty ? "붙여넣은 원문" : title)", type: "evidence",
                body: trimmed, origin: "paste:\(sha.prefix(12))", source: prov)
            refresh()
            errorMessage = nil
        } catch { errorMessage = "수집 실패: \(error.localizedDescription)" }
    }

    /// 파일 원문 수집 — PDF/오디오 추출은 CLI(PDFKit/whisper)에 위임. 백그라운드 실행.
    func captureFile(path: String, project: String?) {
        let cli = Self.cliPath
        errorMessage = "수집 중: \(URL(fileURLWithPath: path).lastPathComponent)…"
        Task.detached { [weak self] in
            let runner = ProcessCommandRunner()
            var args = ["--as", "human", "capture", "--file", path]
            if let project, !project.isEmpty { args += ["--project", project] }
            let result = await runner.run(cli, args, timeout: 2100)
            let ok = result.ok
            let out = result.stdout + result.stderr
            await MainActor.run {
                self?.errorMessage = ok ? nil : "파일 수집 실패: \(out.suffix(160))"
                self?.refresh()
            }
        }
    }

    /// distiller 자가채점 파싱 — 정제본 본문 말미의 "정확성(...): N" 형태에서 축별 점수 추출(초기값 제안).
    func selfRubric(of digest: LedgerDocument) -> [String: Int] {
        var out: [String: Int] = [:]
        for axis in ReviewVerdict.axes {
            // "- 정확성(원문 왜곡 없음): 5 — ..." 같은 줄에서 축 뒤 첫 정수.
            guard let range = digest.head.body.range(of: axis) else { continue }
            let tail = digest.head.body[range.upperBound...]
            if let m = tail.firstMatch(of: /[:：)]\s*([0-5])/) { out[axis] = Int(m.1) }
        }
        return out
    }
}


