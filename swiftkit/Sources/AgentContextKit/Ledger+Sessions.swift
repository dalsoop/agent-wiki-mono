import Foundation
import AgentSessionKit

extension Ledger {
    /// 세션 목록. 세 런타임을 합쳐 최근순.
    public func sessions(tools: Set<AgentTool> = Set(AgentTool.allCases),
                         since: Date? = nil,
                         limit: Int = 200) -> [SessionRef] {
        var refs: [SessionRef] = []
        if tools.contains(.claude) { refs += ClaudeSessionReader().discover(limit: limit, since: since) }
        if tools.contains(.codex) { refs += CodexSessionReader().discover(limit: limit, since: since) }
        if tools.contains(.grok) { refs += GrokSessionReader().discover(limit: limit, since: since) }
        if tools.contains(.agy) { refs += AntigravitySessionReader().discover(limit: limit, since: since) }
        if let since { refs = refs.filter { $0.lastActive >= since } }
        return refs.sorted { $0.lastActive > $1.lastActive }.prefix(limit).map { $0 }
    }

    public func find(sessionId: String) -> SessionRef? {
        // 빠른 경로: id 파일명으로 바로 찾기(전수 discover 1000 회피).
        if let hit = ClaudeSessionReader().find(id: sessionId) { return hit }
        if let hit = CodexSessionReader().find(id: sessionId) { return hit }
        if let hit = GrokSessionReader().find(id: sessionId) { return hit }
        if let hit = AntigravitySessionReader().find(id: sessionId) { return hit }
        // 짧은 prefix 등 — 최근 목록에서만 한 번 더.
        return sessions(limit: 400).first { $0.id == sessionId || $0.id.hasPrefix(sessionId) }
    }

    /// 목록용 행 — 최근 user 포커스 + 대략 모드. 전체 카드보다 가볍다(digest 1회).
    public func sessionRows(tools: Set<AgentTool> = Set(AgentTool.allCases),
                            since: Date? = nil,
                            limit: Int = 200) -> [SessionSummary] {
        sessions(tools: tools, since: since, limit: limit).map { ref in
            let dig = digest(ref)
            let recentRaw = dig.userMessages.last
            let recent = recentRaw.map { oneLine($0, cap: 72) }
            let original = ref.title.map { oneLine($0, cap: 72) }
            // 최근 발언이 첫 제목과 다르면 최근을 보여 "지금 일"을 살린다.
            let core: String
            if let recent, let original, !nearDuplicate(recent, original) {
                core = recent
            } else {
                core = recent ?? original ?? "—"
            }
            let mode = roughMode(commands: dig.commands.count, fileHits: dig.files.values.reduce(0, +))
            let display: String
            if let mode {
                display = "[\(mode)] \(core)"
            } else {
                display = core
            }
            return SessionSummary(ref: ref, displayTitle: display, mode: mode, recentFocus: recent)
        }
    }

    private func oneLine(_ s: String, cap: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= cap ? flat : String(flat.prefix(cap - 1)) + "…"
    }

    private func nearDuplicate(_ a: String, _ b: String) -> Bool {
        let x = String(a.prefix(40))
        let y = String(b.prefix(40))
        return x == y || a.hasPrefix(String(b.prefix(24))) || b.hasPrefix(String(a.prefix(24)))
    }

    /// digest 만으로 대략 모드 — SessionScan 전체 패스 없이 목록에 쓴다.
    private func roughMode(commands: Int, fileHits: Int) -> String? {
        if commands == 0 && fileHits == 0 { return nil }
        if commands >= max(fileHits, 1) * 2 && commands >= 8 { return "bash" }
        if fileHits >= max(commands, 1) && fileHits >= 5 { return "read" }
        if commands >= 5 && fileHits >= 5 { return "mixed" }
        if commands >= 5 { return "bash" }
        return nil
    }

    /// 세션 1건의 전체 컨텍스트 카드.
    public func card(for ref: SessionRef) -> SessionContextCard {
        let digest = digest(ref)
        let scan = SessionScan.scan(ref)
        let blocks = InjectionEvidence.blocks(ref)
        // Codex 는 주입 원문에 그때의 cwd 가 같이 실린다. 세션 메타의 cwd 와 다르면
        // 주입 시점 기준이 더 정확하다.
        let cwd = blocks.compactMap(\.cwd).first ?? ref.cwd

        // 증거의 강도 순으로 주입 스택을 정한다:
        // ① 래퍼가 실행 시점에 내용까지 기록했다 → 그게 정본(reconstructed-exact)
        // ② 아니면 탐색 규칙으로 재구성하고, 로그에 원문이 있으면 승격(injected)
        let launch = launchStore.load(sessionId: ref.id)
        var injected = launch.map(launchStore.injectedDocs)
            ?? InjectionEvidence.reconcile(resolver.resolve(tool: ref.tool, cwd: cwd), with: blocks)

        // 세션 도중 끌려 들어온 md(SKILL.md · agents/*.md)도 같은 스택에 합류시킨다.
        // 루트 지침만 세면 "무슨 문서가 물렸나" 에 반만 답한 것이다.
        let activationDocs = ActivationTrace.docs(from: scan.activations, cwd: cwd, home: home)
        let known = Set(injected.map(\.path))
        injected += activationDocs.filter { !known.contains($0.path) }

        // 활성화에 해석된 md 경로를 되채운다(화면이 이름 옆에 경로를 같이 보여주도록).
        let activations = scan.activations.map { a in
            Activation(
                kind: a.kind, name: a.name, at: a.at, thought: a.thought,
                // 로그에 경로가 찍혀 있으면 그게 정답이다 — 이름으로 되찾지 않는다.
                mdPath: a.mdPath
                    ?? (a.kind == .skill
                    ? ActivationTrace.skillPath(a.name, cwd: cwd, home: home)
                    : ActivationTrace.agentPath(a.name, cwd: cwd, home: home)))
        }

        let touched = DocumentTrace.touched(digest: digest)
        let codeFocus = HeadAnalysis.codeFocus(from: digest)
        let injectedTokens = injected.compactMap(\.approxTokens).reduce(0, +)
        // 래퍼 기록이 있으면 그 세션은 시점 내용까지 안다 — 재구성 경고를 띄우지 않는다.
        let injectionObservable = launch != nil || resolver.injectionObservable(ref.tool)
        let blind = resolver.injectBlindSpots(
            tool: ref.tool, cwd: cwd, already: Set(injected.map(\.path))
        )
        var head = HeadAnalysis.glance(
            tools: scan.tools,
            injected: injected,
            injectedApproxTokens: injectedTokens,
            injectionObservable: injectionObservable,
            touched: touched,
            codeFocus: codeFocus,
            truncated: digest.truncated
        )
        if !blind.isEmpty {
            // 사각을 blurb 끝에 붙인다 — 주입 목록과 섞지 않기 위해 head 만 갱신.
            let names = blind.map { ($0.path as NSString).lastPathComponent }.joined(separator: ", ")
            head = HeadGlance(
                mode: head.mode,
                blurb: head.blurb + " · walk 밖 정본 \(names)(사각)",
                tools: .init(
                    bashCalls: head.bashCalls,
                    readCalls: head.readCalls,
                    editCalls: head.editCalls,
                    totalToolCalls: head.totalToolCalls
                ),
                docs: .init(
                    injectedDocCount: head.injectedDocCount,
                    injectedApproxTokens: head.injectedApproxTokens,
                    injectionObserved: head.injectionObserved,
                    durableDocCount: head.durableDocCount,
                    ephemeralDocCount: head.ephemeralDocCount,
                    codeFocusCount: head.codeFocusCount
                ),
                truncated: head.truncated
            )
        }
        let evidence: [ShellSnippet]
        if !digest.commandOutputs.isEmpty {
            evidence = digest.commandOutputs.suffix(12).map {
                ShellSnippet(command: $0.command, stdoutLine: $0.stdoutLine)
            }
        } else {
            evidence = digest.commands.suffix(12).map { ShellSnippet(command: $0, stdoutLine: nil) }
        }
        return SessionContextCard(
            identity: .init(
                tool: ref.tool.rawValue,
                sessionId: ref.id,
                cwd: cwd,
                title: ref.title,
                lastActive: ref.lastActive,
                messageCount: ref.messageCount,
                truncated: digest.truncated
            ),
            documents: .init(
                injected: injected,
                touched: touched,
                activations: activations,
                skills: scan.skills,
                subagents: scan.subagents,
                tools: scan.tools
            ),
            analysis: .init(
                injectedApproxTokens: injectedTokens,
                injectionObservable: injectionObservable,
                head: head,
                codeFocus: codeFocus,
                injectBlindSpots: blind,
                shellEvidence: evidence
            )
        )
    }

    /// 셸 명령·stdout 첫 줄·사용자/에이전트 발언에서 문자열을 찾는다.
    public func search(
        _ needle: String,
        tools: Set<AgentTool> = Set(AgentTool.allCases),
        since: Date? = nil,
        limit: Int = 80
    ) -> ShellSearchPage {
        let q = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return ShellSearchPage(scanned: 0, hits: []) }
        let refs = sessions(tools: tools, since: since, limit: limit)
        var hits: [ShellSearchHit] = []
        for ref in refs {
            for hit in Self.hits(in: digest(ref), needle: q, sessionId: ref.id, tool: ref.tool.rawValue) {
                hits.append(hit)
                if hits.count >= 50 { break }
            }
            if hits.count >= 50 { break }
        }
        return ShellSearchPage(scanned: refs.count, hits: hits)
    }

    /// 한 digest 안에서 바늘을 찾는다. 셸을 먼저 두고, 그다음 사용자·에이전트·재캡이다.
    public static func hits(
        in digest: SessionDigest,
        needle q: String,
        sessionId: String,
        tool: String
    ) -> [ShellSearchHit] {
        var out: [ShellSearchHit] = []
        let rows: [CommandOutput] = digest.commandOutputs.isEmpty
            ? digest.commands.map { CommandOutput(command: $0, stdoutLine: nil) }
            : digest.commandOutputs
        for row in rows {
            let inCmd = row.command.localizedCaseInsensitiveContains(q)
            let inOut = row.stdoutLine?.localizedCaseInsensitiveContains(q) ?? false
            guard inCmd || inOut else { continue }
            out.append(ShellSearchHit(
                sessionId: sessionId,
                tool: tool,
                command: row.command,
                stdoutLine: row.stdoutLine,
                matched: inOut && !inCmd ? "stdout" : "command"
            ))
        }
        func scan(_ texts: [String], tag: String) {
            for t in texts {
                guard let line = matchingLine(t, q) else { continue }
                out.append(ShellSearchHit(
                    sessionId: sessionId,
                    tool: tool,
                    command: line,
                    stdoutLine: nil,
                    matched: tag
                ))
            }
        }
        scan(digest.userMessages, tag: "user")
        scan(digest.agentMessages, tag: "agent")
        scan(digest.recaps, tag: "recap")
        return out
    }

    static func matchingLine(_ hay: String, _ q: String, cap: Int = 160) -> String? {
        for raw in hay.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.localizedCaseInsensitiveContains(q) else { continue }
            return line.count <= cap ? line : String(line.prefix(cap - 1)) + "…"
        }
        guard hay.localizedCaseInsensitiveContains(q) else { return nil }
        let t = hay.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= cap ? t : String(t.prefix(cap - 1)) + "…"
    }
}
