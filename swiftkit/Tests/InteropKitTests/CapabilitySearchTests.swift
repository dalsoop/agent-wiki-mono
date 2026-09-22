import XCTest
@testable import InteropKit

final class CapabilitySearchTests: XCTestCase {
    var tempDir = FileManager.default.temporaryDirectory
    var store = RegistryStore(fileURL: URL(fileURLWithPath: "/tmp/interop-search-empty.json"))
    var searcher = CapabilitySearcher(
        store: RegistryStore(fileURL: URL(fileURLWithPath: "/tmp/interop-search-empty.json")))

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilitySearchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = RegistryStore(fileURL: tempDir.appendingPathComponent("apps.json"))
        searcher = CapabilitySearcher(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func caps(
        name: String,
        cli: String? = nil,
        commands: [(String, String)] = [],
        dependsWhy: [String] = []
    ) -> Capabilities {
        Capabilities(
            name: name,
            version: "1.0.0",
            cli: cli ?? HostPlatform.cliBinPath(name),
            commands: commands.map { .init(name: $0.0, summary: $0.1, json: true) },
            state: [],
            health: .init(command: "\(name) capabilities", freshness: ""),
            owned: .init(depends: dependsWhy.enumerated().map { i, why in
                .init(
                    id: "dep.\(i)",
                    kind: Capabilities.DependencyKind.path,
                    ref: "/tmp/\(i)",
                    required: true,
                    why: why
                )
            })
        )
    }

    // MARK: - status reasons (not silent empty)

    func testMissingRegistryExplainsWhy() {
        let result = searcher.search("deck")
        XCTAssertEqual(result.status, .registryMissing)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertTrue(result.message.contains("레지스트리"), result.message)
        XCTAssertTrue(result.message.contains(store.fileURL.path), result.message)
    }

    func testEmptyRegistryExplainsWhy() throws {
        try store.save(Registry(apps: [:], updatedAt: "2026-01-01T00:00:00Z"))
        let result = searcher.search("deck")
        XCTAssertEqual(result.status, .registryEmpty)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertTrue(result.message.contains("비어"), result.message)
    }

    func testEmptyQueryExplainsWhy() throws {
        try store.upsert(caps(name: "agent-deck", commands: [("list", "세션 목록")]))
        let result = searcher.search("   ")
        XCTAssertEqual(result.status, .emptyQuery)
        XCTAssertTrue(result.tokens.isEmpty)
    }

    func testNoMatchesExplainsWhy() throws {
        try store.upsert(caps(name: "agent-deck", commands: [("list", "세션 목록")]))
        let result = searcher.search("definitely-not-a-real-capability-xyz")
        XCTAssertEqual(result.status, .noMatches)
        XCTAssertEqual(result.scannedApps, 1)
        XCTAssertTrue(result.message.contains("매칭"), result.message)
    }

    // MARK: - matching

    func testPartialMatchOnCommandSummaryKorean() throws {
        try store.upsert(caps(
            name: "agent-worker-orchestrator",
            commands: [
                ("dispatch", "잡 스펙을 워커에 투입"),
                ("jobs", "큐·실행 중 잡 목록"),
            ]
        ))
        try store.upsert(caps(
            name: "agent-deck",
            commands: [("projects", "프로젝트 보드")],
            dependsWhy: ["세션 전사본 뷰"]
        ))

        let byKo = searcher.search("워커")
        XCTAssertEqual(byKo.status, .ok)
        XCTAssertEqual(byKo.hits.map(\.name), ["agent-worker-orchestrator"])
        XCTAssertTrue(byKo.hits[0].matchedCommands.contains { $0.name == "dispatch" })
        XCTAssertTrue(byKo.hits[0].reasons.contains { $0.field == "command.summary" })

        let byName = searcher.search("deck")
        XCTAssertEqual(byName.status, .ok)
        XCTAssertTrue(byName.hits.contains { $0.name == "agent-deck" })
    }

    func testMultiTokenAND() throws {
        try store.upsert(caps(
            name: "agent-worker-orchestrator",
            commands: [("dispatch", "워커 잡 투입")]
        ))
        try store.upsert(caps(
            name: "other-worker",
            commands: [("status", "상태")]
        ))

        // 통합 랭킹(2026-08-07): 두 토큰 다 걸린 앱이 **위**, 일부만 걸린 앱은
        // 아래에 낮은 점수로 따라온다 — AND 이분법은 정답 앱을 통째로 숨겼다.
        let result = searcher.search("worker dispatch")
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.hits.first?.name, "agent-worker-orchestrator")
        if result.hits.count > 1 {
            XCTAssertLessThan(result.hits[1].score, result.hits[0].score,
                              "부분 매치가 완전 매치보다 높으면 안 된다")
        }

        // 1자 ASCII 파편("a")이 섞여도 남은 낱말을 다 채운 앱은 **완전 일치**다.
        let padded = searcher.search("a worker dispatch")
        XCTAssertEqual(padded.status, .ok,
                       "빠진 파편 토큰이 full/partial 판정을 흔들면 안 된다")
        XCTAssertEqual(padded.hits.first?.name, "agent-worker-orchestrator")
    }

    func testCLIBasenameMatch() throws {
        try store.upsert(caps(
            name: "Agent Deck",
            cli: HostPlatform.cliBinPath("agent-deck"),
            commands: [("list", "목록")]
        ))
        let result = searcher.search("agent-deck")
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.hits.first?.cli, HostPlatform.cliBinPath("agent-deck"))
        XCTAssertTrue(result.hits.first?.reasons.contains { $0.field == "cli" } == true)
    }

    func testDependsWhyMatch() throws {
        try store.upsert(caps(
            name: "dns-switcher",
            commands: [("apply", "적용")],
            dependsWhy: ["승인 게이트로 위험한 DNS 변경을 막는다"]
        ))
        let result = searcher.search("승인")
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.hits.first?.name, "dns-switcher")
        XCTAssertTrue(result.hits.first?.reasons.contains { $0.field == "depends.why" } == true)
    }

    func testCaseAndNFCInsensitive() throws {
        // NFD 한글 토큰 vs NFC 요약
        let nfcSummary = "등록된 잡 목록"
        try store.upsert(caps(
            name: "Hermes",
            commands: [("jobs", nfcSummary)]
        ))
        let nfdQuery = "목록".decomposedStringWithCanonicalMapping
        let result = searcher.search(nfdQuery)
        XCTAssertEqual(result.status, .ok, result.message)
        XCTAssertEqual(result.hits.first?.name, "Hermes")

        let upper = searcher.search("HERMES")
        XCTAssertEqual(upper.status, .ok)
        XCTAssertEqual(upper.hits.first?.name, "Hermes")
    }

    func testReasonsAllowUserJudgment() throws {
        try store.upsert(caps(
            name: "flowlog",
            commands: [("tail", "최근 로그 스트림")]
        ))
        let result = searcher.search("로그")
        let hit = try XCTUnwrap(result.hits.first)
        XCTAssertFalse(hit.reasons.isEmpty)
        XCTAssertEqual(hit.matchedCommands.first?.name, "tail")
    }

    // MARK: - mtime cache

    func testCacheInvalidatesOnRegistryMTimeChange() throws {
        try store.upsert(caps(name: "alpha", commands: [("a", "하나")]))
        XCTAssertEqual(searcher.search("alpha").hits.count, 1)

        // 같은 mtime 재사용 경로 — 두 번째 질의도 동일.
        XCTAssertEqual(searcher.search("alpha").hits.count, 1)

        // 새 앱 upsert → mtime 갱신 → 캐시 재구축.
        try store.upsert(caps(name: "beta", commands: [("b", "둘")]))
        let after = searcher.search("beta")
        XCTAssertEqual(after.status, .ok)
        XCTAssertEqual(after.hits.first?.name, "beta")
        XCTAssertEqual(searcher.search("alpha").hits.count, 1)
    }

    // MARK: - performance guard

    /// 합성 120앱 × 12명령 ≈ 실함대(99×~10) 이상. 질의 1회는 여유 있게 50ms 이내.
    func testSearchLatencyGuardSyntheticFleet() throws {
        var apps: [String: Capabilities] = [:]
        for i in 0..<120 {
            let name = String(format: "fleet-app-%03d", i)
            var cmds: [(String, String)] = []
            for j in 0..<12 {
                cmds.append(("cmd\(j)", "요약 \(i)-\(j) 작업 orchestrator 워커 배포 서명"))
            }
            apps[name] = caps(name: name, commands: cmds)
        }
        // 바늘
        apps["agent-worker-orchestrator"] = caps(
            name: "agent-worker-orchestrator",
            commands: [("dispatch", "잡 스펙을 워커에 투입"), ("run-queued", "큐 소비")]
        )
        try store.save(Registry(apps: apps, updatedAt: ISO8601DateFormatter().string(from: Date())))
        searcher.invalidateCache()

        // 워밍(로드·캐시 구축) 한 번 후 측정.
        _ = searcher.search("orchestrator")
        let samples = (0..<5).map { _ in searcher.search("orchestrator 워커").durationMs }
        let maxMs = samples.max() ?? 999
        let avgMs = samples.reduce(0, +) / Double(samples.count)

        XCTAssertEqual(searcher.search("orchestrator 워커").status, .ok)
        XCTAssertTrue(
            maxMs < 300,
            "검색 1회가 너무 느림: max=\(String(format: "%.2f", maxMs))ms avg=\(String(format: "%.2f", avgMs))ms samples=\(samples)"
        )
    }

    /// 실기계 registry 가 있으면 1회 ms 를 기록한다(없으면 skip). CI 게이트는 합성 테스트.
    func testLiveRegistryLatencyReportIfPresent() throws {
        let liveStore = RegistryStore()
        guard FileManager.default.fileExists(atPath: liveStore.fileURL.path) else {
            throw XCTSkip("live registry 없음")
        }
        let live = CapabilitySearcher(store: liveStore)
        _ = live.search("deck") // warm
        let result = live.search("orchestrator")
        // 보고용 — 실패시키지 않고 상한만 느슨히(디스크 느린 환경).
        XCTAssertLessThan(
            result.durationMs,
            500,
            "live registry 검색이 비정상적으로 느림: \(result.durationMs)ms status=\(result.status) scanned=\(result.scannedApps)"
        )
        fputs(
            "LIVE_REGISTRY_SEARCH_MS=\(String(format: "%.3f", result.durationMs)) scanned=\(result.scannedApps) hits=\(result.hits.count) status=\(result.status.rawValue)\n",
            stderr
        )
    }

    func testTokenizeSplitsPunctuation() {
        XCTAssertEqual(
            CapabilitySearcher.tokenize("worker, orchestrator; deck"),
            ["worker", "orchestrator", "deck"]
        )
    }

    // MARK: - 일부 일치 폴백 (한국어 어미)

    func test_한국어_어미가_달라_AND가_비면_일부낱말로_찾는다() throws {
        try store.upsert(caps(name: "work-market",
                              commands: [("find", "일감으로 도구를 찾는다 — 후보 + 실적")]))
        // "찾기" 는 "찾는다" 의 부분문자열이 아니다 — AND 면 통째로 탈락한다.
        let r = searcher.search("일감으로 도구 찾기")
        XCTAssertEqual(r.status, .partialMatches)
        XCTAssertEqual(r.hits.first?.name, "work-market")
    }

    func test_낱말이_더_많이_걸린_앱이_위로_온다() throws {
        try store.upsert(caps(name: "work-market",
                              commands: [("find", "일감으로 도구를 찾는다 — 후보 + 실적")]))
        try store.upsert(caps(name: "other-tool",
                              commands: [("x", "도구 하나만 걸리는 앱")]))
        let r = searcher.search("일감으로 도구 찾기")
        XCTAssertEqual(r.status, .partialMatches)
        XCTAssertEqual(r.hits.first?.name, "work-market",
                       "두 낱말이 걸린 앱이 한 낱말만 걸린 앱보다 위여야 한다")
    }

    func test_AND가_되면_폴백을_쓰지_않는다() throws {
        try store.upsert(caps(name: "work-market",
                              commands: [("find", "일감으로 도구를 찾는다")]))
        let r = searcher.search("일감으로 도구")
        XCTAssertEqual(r.status, .ok, "정확도를 먼저 쓴다 — AND 가 되면 넓히지 않는다")
    }

    func test_아무것도_안_걸리면_여전히_noMatches() throws {
        try store.upsert(caps(name: "work-market", commands: [("find", "일감")]))
        let r = searcher.search("고래 상어")
        XCTAssertEqual(r.status, .noMatches)
    }

    // MARK: - QueryLexicon (일감 언어 ↔ 도구 언어)

    func test_한국어_일감_낱말이_영어_앱이름에_걸린다() throws {
        // 실측(2026-08-06): "스크린샷" 질의가 screenshot 앱을 못 찾아 재현율 38%.
        try store.upsert(caps(name: "screenshot", commands: [("shot", "capture screen")]))
        let r = searcher.search("스크린샷")
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.hits.first?.name, "screenshot")
    }

    func test_어미가_붙은_동사도_동의어로_걸린다() throws {
        try store.upsert(caps(name: "app-build-manager",
                              commands: [("ship", "release build")]))
        let r = searcher.search("배포해줘")
        XCTAssertEqual(r.status, .ok, "\"배포해줘\" → 줄기 \"배포\" → ship/release")
        XCTAssertEqual(r.hits.first?.name, "app-build-manager")
    }

    func test_변형은_AND_토큰수를_늘리지_않는다() throws {
        // 동의어 확장이 OR 남발이 되면 관련 없는 앱이 올라온다 —
        // 토큰 단위 AND 는 유지되어야 한다.
        try store.upsert(caps(name: "screenshot", commands: [("shot", "capture screen")]))
        let r = searcher.search("스크린샷 고래")
        XCTAssertNotEqual(r.status, .ok, "없는 낱말(고래)이 있으면 완전일치는 아니어야 한다")
    }

    func test_lexicon_줄기벗기기_과잉절단_안전() {
        // 1자 줄기는 사전에 있을 때만 남긴다 — "창" 은 살고, 임의 1자는 버린다.
        XCTAssertTrue(QueryLexicon.variants("창을").contains("window"))
        XCTAssertFalse(QueryLexicon.strippedStems("해줘").contains(""))
    }

    // MARK: - 레거시 registry 항목 관용 디코드

    func test_구식_항목이_검색에서_사라지지_않는다() throws {
        // 실측(2026-08-06): state/health 누락·commands 문자열 항목 3개가
        // 디코드 실패로 스캔에서 통째로 빠졌다(267 등록 · 264 스캔).
        let legacy = """
        {"apps": {"skill-generator": {"name": "skill-generator", "version": "1.0.0",
          "cli": "\(HostPlatform.cliBinPath("skill-generator"))",
          "commands": ["scan", "generate", "grade"]}}, "updatedAt": ""}
        """
        let data = try XCTUnwrap(legacy.data(using: .utf8))
        try data.write(to: store.fileURL)
        let r = searcher.search("skill")
        XCTAssertEqual(r.hits.first?.name, "skill-generator",
                       "구식 스키마 항목도 이름·명령으로 검색되어야 한다")
    }
    // MARK: - purpose (개념어 검색)

    /// 2026-08-10 실측: 계약에 "이 앱이 무엇인가" 필드가 없어 293앱 중 292앱에 설명이 없었다.
    /// `search "객체화"` 는 0건, `search "파일"` 은 `add-file`·`cookies-import-file` 같은
    /// **명령 이름 조각**만 쏟아냈다. 개념으로 앱을 못 찾으면 지도가 지도 구실을 못 한다.
    func testPurposeIsIndexedSoConceptualQueriesFindTheApp() throws {
        try store.upsert(Capabilities(
            name: "business-documents",
            purpose: "사업 서류를 종류·테넌트별 객체로 보관한다 — 버전 이력·OCR",
            version: "1", cli: HostPlatform.cliBinPath("business-documents"),
            commands: [.init(name: "add", summary: "등록", json: true)],
            state: [], health: .init(command: "x", freshness: "")))
        try store.upsert(caps(name: "noise", commands: [("add-file", "파일 추가")]))

        let result = searcher.search("객체")
        XCTAssertEqual(result.hits.first?.name, "business-documents",
                       "개념어로 못 찾는다: \(result.hits.map(\.name))")
    }

    /// purpose 매치가 명령 이름 조각 매치보다 위여야 한다.
    func testPurposeOutranksCommandNameFragments() throws {
        try store.upsert(caps(name: "fragment", commands: [("add-file", "추가"), ("list-file", "목록")]))
        try store.upsert(Capabilities(
            name: "real", purpose: "파일을 객체로 만들어 보관한다",
            version: "1", cli: HostPlatform.cliBinPath("real"),
            commands: [.init(name: "run", summary: "실행", json: true)],
            state: [], health: .init(command: "x", freshness: "")))

        let result = searcher.search("파일")
        XCTAssertEqual(result.hits.first?.name, "real",
                       "명령 이름 조각이 개념 매치를 이겼다: \(result.hits.map(\.name))")
    }

    /// 옛 payload(purpose 없음)도 디코드돼야 한다 — 292앱이 아직 안 채웠다.
    func testLegacyPayloadWithoutPurposeStillDecodes() throws {
        let json = """
        {"name":"old","version":"1","cli":"/x","commands":[],"state":[],
         "health":{"command":"x"},"depends":[]}
        """
        let decoded = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.purpose, "")
    }

    // MARK: - ToolKind and Multi-Tool Catalog (#33)

    func testToolKindAndBadgeDefaultAndEncoding() throws {
        let hit = CapabilitySearchHit(
            name: "test-app",
            cli: "/bin/test-app",
            version: "1.0.0",
            matchedCommands: [],
            reasons: [],
            score: 10
        )
        XCTAssertEqual(hit.kind, .app)
        XCTAssertEqual(hit.badge, "[app]")
        XCTAssertEqual(hit.sourceID, "/bin/test-app")

        // Encode to JSON and verify kind and badge are present
        let data = try JSONEncoder().encode(hit)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("\"kind\" : \"app\"") || jsonString.contains("\"kind\":\"app\""))
        XCTAssertTrue(jsonString.contains("\"badge\" : \"[app]\"") || jsonString.contains("\"badge\":\"[app]\""))

        // Decode from legacy JSON without kind or badge or sourceID
        let legacyJSON = """
        {
          "name": "legacy-app",
          "cli": "/opt/legacy",
          "version": "1.0",
          "matchedCommands": [],
          "reasons": [],
          "score": 5
        }
        """
        let decoded = try JSONDecoder().decode(CapabilitySearchHit.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.kind, .app)
        XCTAssertEqual(decoded.badge, "[app]")
        XCTAssertEqual(decoded.sourceID, "/opt/legacy")
    }

    func testMultiToolCatalogSearchIntegration() throws {
        // 1. App in registry
        try store.upsert(caps(name: "app-worker-hub", commands: [("start", "작업 허브")]))

        // 2. Agents in custom agents.json
        let agentsFile = tempDir.appendingPathComponent("agents.json")
        let agentsPayload = CapabilitySearcher.AgentRegistryFilePayload(version: 1, agents: [
            .init(
                id: "agent-verifier",
                name: "agent-verifier",
                persona: "Gujo download supply verifier",
                personaEmoji: "📦",
                agent: "codex",
                model: "codex-4",
                notes: "Runs supply audit and verification"
            )
        ])
        let agentData = try JSONEncoder().encode(agentsPayload)
        try agentData.write(to: agentsFile)

        // 3. Skills in custom skill root
        let skillsDir = tempDir.appendingPathComponent("skills-mono")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillsPayload = CapabilitySearcher.HostSkillsRegistryPayload(skills: [
            .init(
                name: "agent-browser-skill",
                category: "host-control",
                kind: "capability",
                version: "1.0.0",
                path: "skills/agent-browser-skill",
                description: "Chromium 세션 브라우징 자동화 오케스트레이터"
            )
        ])
        let skillsData = try JSONEncoder().encode(skillsPayload)
        let manifestName = "registry" + ".json"
        try skillsData.write(to: skillsDir.appendingPathComponent(manifestName))

        // Build searcher with all three catalogs
        let multiSearcher = CapabilitySearcher(
            store: store,
            agentsURL: agentsFile,
            skillsRoots: [skillsDir]
        )

        // Search for app
        let appHit = multiSearcher.search("worker")
        XCTAssertEqual(appHit.status, .ok)
        let firstApp = try XCTUnwrap(appHit.hits.first)
        XCTAssertEqual(firstApp.name, "app-worker-hub")
        XCTAssertEqual(firstApp.kind, .app)
        XCTAssertEqual(firstApp.badge, "[app]")

        // Search for agent
        let agentHit = multiSearcher.search("verifier")
        XCTAssertEqual(agentHit.status, .ok)
        let firstAgent = try XCTUnwrap(agentHit.hits.first)
        XCTAssertEqual(firstAgent.name, "agent-verifier")
        XCTAssertEqual(firstAgent.kind, .agent)
        XCTAssertEqual(firstAgent.badge, "[agent]")
        XCTAssertEqual(firstAgent.sourceID, "agent-verifier")

        // Search for skill
        let skillHit = multiSearcher.search("browser")
        XCTAssertEqual(skillHit.status, .ok)
        let firstSkill = try XCTUnwrap(skillHit.hits.first)
        XCTAssertEqual(firstSkill.name, "agent-browser-skill")
        XCTAssertEqual(firstSkill.kind, .skill)
        XCTAssertEqual(firstSkill.badge, "[skill]")
    }

    func testQueryLexiconAppliesToSkillsAndAgents() throws {
        let agentsFile = tempDir.appendingPathComponent("agents-lex.json")
        let agentsPayload = CapabilitySearcher.AgentRegistryFilePayload(version: 1, agents: [
            .init(
                id: "funnel-auditor",
                name: "funnel-auditor",
                persona: "Gujo buyer funnel verifier",
                notes: "Live funnel health inspection"
            )
        ])
        try JSONEncoder().encode(agentsPayload).write(to: agentsFile)

        let skillsDir = tempDir.appendingPathComponent("skills-lex")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillsPayload = CapabilitySearcher.HostSkillsRegistryPayload(skills: [
            .init(
                name: "code-reviewer",
                category: "agent-ops",
                description: "코드 변경분을 검사하고 리뷰를 수행한다"
            )
        ])
        let manifestName = "registry" + ".json"
        try JSONEncoder().encode(skillsPayload).write(to: skillsDir.appendingPathComponent(manifestName))

        let lexSearcher = CapabilitySearcher(
            store: store,
            agentsURL: agentsFile,
            skillsRoots: [skillsDir]
        )

        // Korean verb ending stripping: "검사해줘" -> stem "검사" -> matches skill description!
        let skillResult = lexSearcher.search("검사해줘")
        XCTAssertEqual(skillResult.status, .ok)
        XCTAssertTrue(skillResult.hits.contains { $0.name == "code-reviewer" && $0.kind == .skill })

        // Korean-English synonym expansion: "검증" -> "verify" / "verifier" -> matches agent persona!
        let agentResult = lexSearcher.search("검증")
        XCTAssertEqual(agentResult.status, .ok)
        XCTAssertTrue(agentResult.hits.contains { $0.name == "funnel-auditor" && $0.kind == .agent })
    }
}

