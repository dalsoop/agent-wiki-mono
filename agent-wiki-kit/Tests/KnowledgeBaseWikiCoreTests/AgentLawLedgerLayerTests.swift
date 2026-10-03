import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

/// ledger 3 원장 계층(전신·테넌트 대응·기기 키). 근거: 결정 0007, business-rules "원장 구성"·"전신".
@Suite struct AgentLawLedgerLayerTests {
    /// 명세의 원장 셋 + 전신 셋. 옛 tenant-gujo 는 ledger 2 시절 gujo-wiki 아래 tenant.
    private func agentLawCatalog() -> WorldBindingCatalog {
        WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/fx/gujo-wiki", layer: "remoteShared"),
            BoundWorld(name: "person-yun-jeonghan", rootPath: "/tmp/fx/person-yun-jeonghan"),
            BoundWorld(name: "tenant-gujo", rootPath: "/tmp/fx/tenant-gujo", layer: "tenant", parent: "gujo-wiki"),
            BoundWorld(
                name: "agent-law", rootPath: "/tmp/fx/agent-law/law",
                key: "law", predecessor: "gujo-wiki"),
            BoundWorld(
                name: "agent-law-person-yun-jeonghan", rootPath: "/tmp/fx/agent-law/person-yun-jeonghan",
                layer: "tenant", parent: "agent-law",
                key: "person-yun-jeonghan", predecessor: "person-yun-jeonghan"),
            BoundWorld(
                name: "agent-law-tenant-gujo", rootPath: "/tmp/fx/agent-law/tenant-gujo",
                layer: "tenant", parent: "agent-law",
                key: "tenant-gujo", predecessor: "tenant-gujo"),
        ])
    }

    private func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-kit-agent-law-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: 설정 모델

    @Test func legacyConfigFileStillDecodes() throws {
        let dir = temporaryDirectory("legacy")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        let legacy = """
        {"currentWorld":"gujo-wiki","worlds":[
          {"name":"gujo-wiki","rootPath":"/tmp/g","layer":"remoteShared"},
          {"name":"tenant-a","rootPath":"/tmp/a","layer":"tenant","parent":"gujo-wiki","display":"A"}
        ]}
        """
        try Data(legacy.utf8).write(to: url)
        let file = WorldConfigStore.load(from: url)
        #expect(file.effectiveWorlds.count == 2)
        #expect(file.currentWorld == "gujo-wiki")
        #expect(file.tenantMap == nil)
        #expect(file.devices == nil)
        #expect(file.currentDevice == nil)
        #expect(file.dreamDevice == nil)
        let tenant = file.effectiveWorlds.first { $0.name == "tenant-a" }
        #expect(tenant?.parent == "gujo-wiki")
        #expect(tenant?.key == nil)
        #expect(tenant?.predecessor == nil)
        let config = try JSONDecoder().decode(LedgerConfig.self, from: Data(legacy.utf8))
        #expect(config.effectiveWorlds.count == 2)
    }

    @Test func ledgerThreeFieldsRoundTripInTempFile() throws {
        let dir = temporaryDirectory("roundtrip")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let file = BoundLedgerFile(
            worlds: agentLawCatalog().worlds,
            currentWorld: "agent-law",
            tenantMap: ["personal": "agent-law-person-yun-jeonghan", "gujo": "agent-law-tenant-gujo"],
            devices: ["macbook"],
            currentDevice: "macbook",
            dreamDevice: "macbook")
        try WorldConfigStore.save(file, to: url)
        let loaded = WorldConfigStore.load(from: url)
        #expect(loaded.tenantMap?["gujo"] == "agent-law-tenant-gujo")
        #expect(loaded.devices == ["macbook"])
        #expect(loaded.currentDevice == "macbook")
        #expect(loaded.dreamDevice == "macbook")
        let law = loaded.effectiveWorlds.first { $0.name == "agent-law" }
        #expect(law?.key == "law")
        #expect(law?.predecessor == "gujo-wiki")
        // 옛 LedgerConfig 도 새 필드가 있는 파일을 읽는다.
        let config = try JSONDecoder().decode(LedgerConfig.self, from: Data(contentsOf: url))
        #expect(config.effectiveWorlds.contains { $0.name == "agent-law" })
    }

    @Test func ledgerKeyFormat() {
        #expect(LedgerKeyFormat.isValid("law"))
        #expect(LedgerKeyFormat.isValid("person-yun-jeonghan"))
        #expect(LedgerKeyFormat.isValid("a1"))
        #expect(!LedgerKeyFormat.isValid("a"))
        #expect(!LedgerKeyFormat.isValid("1law"))
        #expect(!LedgerKeyFormat.isValid("Law"))
        #expect(!LedgerKeyFormat.isValid("law_x"))
        #expect(!LedgerKeyFormat.isValid(""))
        #expect(LedgerKeyFormat.isValid("a" + String(repeating: "b", count: 40)))
        #expect(!LedgerKeyFormat.isValid("a" + String(repeating: "b", count: 41)))
    }

    @Test func agentLawNameIsRemoteShared() {
        #expect(WikiWorldPresentation.classify(name: "agent-law", rootPath: "/tmp/x/law") == .remoteShared)
        #expect(agentLawCatalog().resolvedLayer(of: "agent-law") == .remoteShared)
    }

    // MARK: 설정 변경

    @Test func addingAgentLawLedgersSucceeds() throws {
        var file = BoundLedgerFile(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/g", layer: "remoteShared"),
            BoundWorld(name: "person-yun-jeonghan", rootPath: "/tmp/p"),
        ])
        file = try WorldMutation.adding(
            to: file, name: "agent-law", path: "/tmp/al/law", layer: nil, parent: nil,
            key: "law", predecessor: "gujo-wiki").get()
        file = try WorldMutation.adding(
            to: file, name: "agent-law-person-yun-jeonghan", path: "/tmp/al/p",
            layer: "tenant", parent: "agent-law",
            key: "person-yun-jeonghan", predecessor: "person-yun-jeonghan").get()
        let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
        #expect(catalog.world(named: "agent-law")?.key == "law")
        #expect(catalog.parentName(of: "agent-law-person-yun-jeonghan") == "agent-law")
        #expect(catalog.isArchived("gujo-wiki"))
        #expect(catalog.isArchived("person-yun-jeonghan"))
        #expect(!catalog.isArchived("agent-law"))
    }

    @Test func addingRejectsBadKeyAndKeyChange() throws {
        let base = BoundLedgerFile(worlds: [
            BoundWorld(name: "agent-law", rootPath: "/tmp/al/law", key: "law"),
            BoundWorld(name: "other", rootPath: "/tmp/o", key: "other-key"),
        ])
        let bad = WorldMutation.adding(
            to: base, name: "x", path: "/tmp/x", layer: nil, parent: nil, key: "Bad_Key")
        #expect(failureMessage(bad)?.contains("ledger key") ?? false)

        let changed = WorldMutation.adding(
            to: base, name: "agent-law", path: "/tmp/al/law", layer: nil, parent: nil, key: "law2")
        #expect(failureMessage(changed)?.contains("immutable") ?? false)

        let duplicate = WorldMutation.adding(
            to: base, name: "new", path: "/tmp/n", layer: nil, parent: nil, key: "law")
        #expect(failureMessage(duplicate)?.contains("already used") ?? false)

        // 같은 키로 다시 쓰기, 키 생략 재등록은 키를 유지한다.
        let same = try WorldMutation.adding(
            to: base, name: "agent-law", path: "/tmp/al/law", layer: nil, parent: nil, key: "law").get()
        #expect(same.effectiveWorlds.first { $0.name == "agent-law" }?.key == "law")
        let omitted = try WorldMutation.adding(
            to: base, name: "agent-law", path: "/tmp/al/law2", layer: nil, parent: nil).get()
        #expect(omitted.effectiveWorlds.first { $0.name == "agent-law" }?.key == "law")
    }

    @Test func predecessorChainRefused() {
        let base = BoundLedgerFile(worlds: agentLawCatalog().worlds)
        // 전신(gujo-wiki)으로 지정된 world 가 자기 전신을 가지려 하면 거부.
        let archivedTakesPredecessor = WorldMutation.adding(
            to: base, name: "gujo-wiki", path: "/tmp/fx/gujo-wiki", layer: nil, parent: nil,
            predecessor: "person-yun-jeonghan")
        #expect(failureMessage(archivedTakesPredecessor)?.contains("chain") ?? false)
        // 전신을 가진 world(agent-law)를 전신으로 삼으면 사슬이 되므로 거부.
        let successorOfSuccessor = WorldMutation.adding(
            to: base, name: "agent-law-next", path: "/tmp/fx/next", layer: nil, parent: nil,
            key: "law-next", predecessor: "agent-law")
        #expect(failureMessage(successorOfSuccessor)?.contains("chain") ?? false)
        let unknown = WorldMutation.adding(
            to: base, name: "n", path: "/tmp/n", layer: nil, parent: nil, predecessor: "nope")
        #expect(failureMessage(unknown)?.contains("unknown predecessor") ?? false)
        let selfPredecessor = WorldMutation.adding(
            to: base, name: "solo", path: "/tmp/s", layer: nil, parent: nil, predecessor: "solo")
        #expect(failureMessage(selfPredecessor) != nil)
        let changed = WorldMutation.adding(
            to: base, name: "agent-law", path: "/tmp/fx/agent-law/law", layer: nil, parent: nil,
            predecessor: "tenant-gujo")
        #expect(failureMessage(changed)?.contains("immutable") ?? false)
    }

    @Test func tenantParentRuleStillHolds() {
        let base = BoundLedgerFile(worlds: agentLawCatalog().worlds)
        let notShared = WorldMutation.adding(
            to: base, name: "t", path: "/tmp/t", layer: "tenant",
            parent: "agent-law-tenant-gujo", key: "tt")
        #expect(failureMessage(notShared)?.contains("remoteShared") ?? false)
        let parentWithoutTenant = WorldMutation.adding(
            to: base, name: "t", path: "/tmp/t", layer: nil, parent: "agent-law", key: "tt")
        #expect(failureMessage(parentWithoutTenant) != nil)
    }

    @Test func tenantMapMutation() throws {
        let base = BoundLedgerFile(worlds: agentLawCatalog().worlds)
        let next = try LedgerThreeConfigMutation.settingTenantMap(
            in: base, tenant: "gujo", world: "agent-law-tenant-gujo").get()
        #expect(next.tenantMap == ["gujo": "agent-law-tenant-gujo"])
        let unknownWorld = LedgerThreeConfigMutation.settingTenantMap(
            in: base, tenant: "gujo", world: "nope")
        #expect(failureMessage(unknownWorld)?.contains("unknown world") ?? false)
        let emptyTenant = LedgerThreeConfigMutation.settingTenantMap(
            in: base, tenant: "  ", world: "agent-law")
        #expect(failureMessage(emptyTenant) != nil)
    }

    @Test func deviceRegistrationIsImmutable() throws {
        let base = BoundLedgerFile(worlds: [])
        let registered = try LedgerThreeConfigMutation.registeringDevice(in: base, key: "macbook").get()
        #expect(registered.devices == ["macbook"])
        #expect(registered.currentDevice == "macbook")
        // 같은 키 재등록은 그대로.
        let again = try LedgerThreeConfigMutation.registeringDevice(in: registered, key: "macbook").get()
        #expect(again.devices == ["macbook"])
        // 다른 기기 키를 목록에만 추가.
        let other = try LedgerThreeConfigMutation.registeringDevice(
            in: registered, key: "mac-mini", asCurrent: false).get()
        #expect(other.devices == ["macbook", "mac-mini"])
        #expect(other.currentDevice == "macbook")
        // 이 기기 키는 바꿀 수 없다.
        let swap = LedgerThreeConfigMutation.registeringDevice(in: registered, key: "mac-mini")
        #expect(failureMessage(swap)?.contains("immutable") ?? false)
        let bad = LedgerThreeConfigMutation.registeringDevice(in: base, key: "Mac Book")
        #expect(failureMessage(bad) != nil)
    }

    @Test func dreamDeviceMustBeRegistered() throws {
        let base = try LedgerThreeConfigMutation.registeringDevice(
            in: BoundLedgerFile(worlds: []), key: "macbook").get()
        let set = try LedgerThreeConfigMutation.settingDreamDevice(in: base, key: "macbook").get()
        #expect(set.dreamDevice == "macbook")
        let unknown = LedgerThreeConfigMutation.settingDreamDevice(in: base, key: "mac-mini")
        #expect(failureMessage(unknown)?.contains("not registered") ?? false)
    }

    // MARK: 인용 게이트

    @Test func citePredecessorOfSameAndAncestorAllowed() {
        let catalog = agentLawCatalog()
        // 같은 원장의 전신
        #expect(WorldCiteGate.evaluate(
            currentWorld: "agent-law-person-yun-jeonghan", citedID: "aaaa",
            citedWorld: "person-yun-jeonghan", catalog: catalog) == nil)
        // 상위 원장의 전신
        #expect(WorldCiteGate.evaluate(
            currentWorld: "agent-law-person-yun-jeonghan", citedID: "bbbb",
            citedWorld: "gujo-wiki", catalog: catalog) == nil)
        // 상위 원장 자체
        #expect(WorldCiteGate.evaluate(
            currentWorld: "agent-law-person-yun-jeonghan", citedID: "cccc",
            citedWorld: "agent-law", catalog: catalog) == nil)
        // 공유 원장의 자기 전신
        #expect(WorldCiteGate.evaluate(
            currentWorld: "agent-law", citedID: "dddd",
            citedWorld: "gujo-wiki", catalog: catalog) == nil)
    }

    @Test func citeSiblingOrDescendantPredecessorRefused() {
        let catalog = agentLawCatalog()
        // 형제 원장의 전신
        let siblingPredecessor = WorldCiteGate.evaluate(
            currentWorld: "agent-law-person-yun-jeonghan", citedID: "eeee",
            citedWorld: "tenant-gujo", catalog: catalog)
        #expect(siblingPredecessor != nil)
        #expect(siblingPredecessor?.message.contains("predecessor") ?? false)
        // 형제 원장 자체
        let sibling = WorldCiteGate.evaluate(
            currentWorld: "agent-law-person-yun-jeonghan", citedID: "ffff",
            citedWorld: "agent-law-tenant-gujo", catalog: catalog)
        #expect(sibling?.message.contains("sibling") ?? false)
        // 하위 원장의 전신
        let descendantPredecessor = WorldCiteGate.evaluate(
            currentWorld: "agent-law", citedID: "9999",
            citedWorld: "person-yun-jeonghan", catalog: catalog)
        #expect(descendantPredecessor != nil)
        // 하위 원장 자체
        let descendant = WorldCiteGate.evaluate(
            currentWorld: "agent-law", citedID: "8888",
            citedWorld: "agent-law-tenant-gujo", catalog: catalog)
        #expect(descendant?.message.contains("upward-only") ?? false)
    }

    @Test func ledgerTwoCiteRulesUnchangedWithPredecessorsPresent() {
        let catalog = WorldBindingCatalog(worlds: agentLawCatalog().worlds + [
            BoundWorld(name: "tenant-x", rootPath: "/tmp/fx/tx", layer: "tenant", parent: "gujo-wiki"),
        ])
        // 옛 테넌트끼리: 형제 거부
        let sibling = WorldCiteGate.evaluate(
            currentWorld: "tenant-x", citedID: "1111", citedWorld: "tenant-gujo", catalog: catalog)
        #expect(sibling?.message.contains("sibling tenant cite refused") ?? false)
        // 옛 공유 → 옛 테넌트: upward-only
        let down = WorldCiteGate.evaluate(
            currentWorld: "gujo-wiki", citedID: "2222", citedWorld: "tenant-x", catalog: catalog)
        #expect(down?.message.contains("upward-only") ?? false)
        // 옛 테넌트 → 옛 공유: 허용
        #expect(WorldCiteGate.evaluate(
            currentWorld: "tenant-x", citedID: "3333", citedWorld: "gujo-wiki", catalog: catalog) == nil)
        // 옛 원장은 후신(전신의 역방향)을 인용하지 못한다.
        #expect(WorldCiteGate.evaluate(
            currentWorld: "gujo-wiki", citedID: "4444", citedWorld: "agent-law", catalog: catalog) != nil)
    }

    // MARK: 쓰기 게이트

    @Test func archivedWorldWriteRefused() {
        let catalog = agentLawCatalog()
        for archived in ["gujo-wiki", "person-yun-jeonghan", "tenant-gujo"] {
            let denial = WorldWriteGate.denial(
                targetWorld: archived, catalog: catalog,
                registeredDevices: ["macbook"], currentDevice: "macbook")
            #expect(denial?.reason == .archivedPredecessor)
            #expect(denial?.message.contains("archived") ?? false)
        }
        #expect(WorldWriteGate.denial(
            targetWorld: "agent-law", catalog: catalog,
            registeredDevices: ["macbook"], currentDevice: "macbook") == nil)
    }

    @Test func unregisteredDeviceRefusedOnlyForLedgerThreeWorlds() {
        let catalog = WorldBindingCatalog(worlds: agentLawCatalog().worlds + [
            BoundWorld(name: "repo-world", rootPath: "/tmp/fx/repo/.wiki"),
        ])
        let none = WorldWriteGate.denial(
            targetWorld: "agent-law", catalog: catalog, registeredDevices: [], currentDevice: nil)
        #expect(none?.reason == .unregisteredDevice)
        let unknown = WorldWriteGate.denial(
            targetWorld: "agent-law-tenant-gujo", catalog: catalog,
            registeredDevices: ["macbook"], currentDevice: "mac-mini")
        #expect(unknown?.reason == .unregisteredDevice)
        #expect(unknown?.message.contains("mac-mini") ?? false)
        // 키만 가진 world 도 ledger 3.
        let keyOnly = WorldBindingCatalog(worlds: [BoundWorld(name: "k", rootPath: "/tmp/k", key: "kk")])
        #expect(WorldWriteGate.denial(
            targetWorld: "k", catalog: keyOnly, registeredDevices: [], currentDevice: nil)?.reason
            == .unregisteredDevice)
        // ledger 2 world 는 기기 키 없이 쓴다.
        #expect(WorldWriteGate.denial(
            targetWorld: "repo-world", catalog: catalog, registeredDevices: [], currentDevice: nil) == nil)
    }

    @Test func writeGateReadsDevicesFromConfigFile() {
        let file = BoundLedgerFile(
            worlds: agentLawCatalog().worlds, devices: ["macbook"], currentDevice: "macbook")
        #expect(WorldWriteGate.denial(targetWorld: "agent-law", file: file) == nil)
        #expect(WorldWriteGate.denial(targetWorld: "gujo-wiki", file: file)?.reason == .archivedPredecessor)
        var unregistered = file
        unregistered.currentDevice = nil
        #expect(WorldWriteGate.denial(targetWorld: "agent-law", file: unregistered)?.reason
            == .unregisteredDevice)
    }

    // MARK: 검색 범위

    @Test func searchScopeIncludesPredecessorsWithMarker() {
        let catalog = agentLawCatalog()
        let entries = WorldSearchScope.entries(current: "agent-law-person-yun-jeonghan", catalog: catalog)
        #expect(entries.map(\.name) == [
            "agent-law-person-yun-jeonghan", "person-yun-jeonghan", "agent-law", "gujo-wiki",
        ])
        let predecessor = entries.first { $0.name == "person-yun-jeonghan" }
        #expect(predecessor?.predecessor == true)
        #expect(predecessor?.predecessorOf == "agent-law-person-yun-jeonghan")
        #expect(entries.first { $0.name == "agent-law" }?.predecessor == false)
        #expect(!entries.contains { $0.name == "tenant-gujo" || $0.name == "agent-law-tenant-gujo" })
        #expect(WorldSearchScope.names(current: "agent-law-person-yun-jeonghan", catalog: catalog)
            == entries.map(\.name))
        let shared = WorldSearchScope.entries(current: "agent-law", catalog: catalog)
        #expect(shared.map(\.name) == ["agent-law", "gujo-wiki"])
    }

    @Test func searchScopeUnchangedWithoutPredecessors() {
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/g", layer: "remoteShared"),
            BoundWorld(name: "tenant-a", rootPath: "/tmp/a", layer: "tenant", parent: "gujo-wiki"),
        ])
        let entries = WorldSearchScope.entries(current: "tenant-a", catalog: catalog)
        #expect(entries.map(\.name) == ["tenant-a", "gujo-wiki"])
        #expect(entries.allSatisfy { !$0.predecessor })
    }

    // MARK: 테넌트 → 원장

    @Test func tenantRouting() {
        let map = ["personal": "agent-law-person-yun-jeonghan", "gujo": "agent-law-tenant-gujo"]
        #expect(TenantLedgerRouting.resolve(tenant: nil, tenantMap: map)
            == .assigned(tenant: "personal", world: "agent-law-person-yun-jeonghan"))
        #expect(TenantLedgerRouting.resolve(tenant: "  ", tenantMap: map)
            == .assigned(tenant: "personal", world: "agent-law-person-yun-jeonghan"))
        #expect(TenantLedgerRouting.resolve(tenant: "gujo", tenantMap: map)
            == .assigned(tenant: "gujo", world: "agent-law-tenant-gujo"))
        let missing = TenantLedgerRouting.resolve(tenant: "family", tenantMap: map)
        #expect(missing == .unassigned(tenant: "family"))
        #expect(missing.worldName == nil)
        #expect(missing.label == "unassigned")
        #expect(TenantLedgerRouting.resolve(tenant: nil, tenantMap: nil) == .unassigned(tenant: "personal"))
    }

    // MARK: 보조

    private func failureMessage(_ result: Result<BoundLedgerFile, WorldMutationFailure>) -> String? {
        if case .failure(let failure) = result { return failure.message }
        return nil
    }
}
