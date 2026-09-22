import Foundation
import os
import Testing
@testable import InteropKit

/// lock 으로 보호한 값 하나를 감싸 Sendable 검사를 통과한다.
private final class ErrorBox: Sendable {
    private let state: OSAllocatedUnfairLock<[String]>
    var messages: [String] { state.withLock { $0 } }
    init() { state = OSAllocatedUnfairLock(initialState: []) }
    func append(_ message: String) { state.withLock { $0.append(message) } }
}

@Suite("레지스트리 upsert")
struct RegistryStoreTests {
    private func makeCaps(name: String, cli: String) -> Capabilities {
        Capabilities(
            name: name, version: "1", cli: cli,
            commands: [.init(name: "status", summary: "상태", json: true)],
            state: [],
            health: .init(command: "\(cli) capabilities", freshness: ""))
    }

    /// 실행 파일 하나와, 그걸 가리키는 심링크를 만든다.
    private func fixture() throws -> (dir: URL, real: String, link: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let real = dir.appendingPathComponent("agent-wiki").path
        FileManager.default.createFile(atPath: real, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let link = dir.appendingPathComponent("knowledge-base-wiki").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        return (dir, real, link)
    }

    @Test("같은 실행 파일을 가리키는 옛 키는 걷어낸다 — 안 그러면 영원히 안 지워진다")
    func prunesAliasKey() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let store = RegistryStore(fileURL: f.dir.appendingPathComponent("registry-store.json"))

        // 별칭 이름으로 먼저 등록된 옛 항목.
        try store.upsert(makeCaps(name: "knowledge-base-wiki", cli: f.link))
        #expect(try store.load().apps["knowledge-base-wiki"] != nil)

        // 진짜 이름으로 등록하면 옛 키가 사라진다.
        try store.upsert(makeCaps(name: "agent-wiki", cli: f.real))
        let apps = try store.load().apps
        #expect(apps["agent-wiki"] != nil)
        #expect(apps["knowledge-base-wiki"] == nil)
    }

    @Test("다른 실행 파일을 쓰는 앱은 건드리지 않는다")
    func keepsUnrelatedApps() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let other = f.dir.appendingPathComponent("other-app").path
        FileManager.default.createFile(atPath: other, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let store = RegistryStore(fileURL: f.dir.appendingPathComponent("registry-store.json"))

        try store.upsert(makeCaps(name: "other-app", cli: other))
        try store.upsert(makeCaps(name: "agent-wiki", cli: f.real))
        let apps = try store.load().apps
        #expect(apps["other-app"] != nil)
        #expect(apps["agent-wiki"] != nil)
    }

    @Test("동시 upsert 는 둘 다 남긴다 — 읽기-수정-쓰기만 있으면 한쪽이 사라진다")
    func concurrentUpsertsKeepBoth() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("registry-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let aBin = dir.appendingPathComponent("app-a").path
        let bBin = dir.appendingPathComponent("app-b").path
        FileManager.default.createFile(
            atPath: aBin, contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        FileManager.default.createFile(
            atPath: bBin, contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        let store = RegistryStore(fileURL: dir.appendingPathComponent("registry-store.json"))
        let group = DispatchGroup()
        let errors = ErrorBox()
        let pairs = [("app-a", aBin), ("app-b", bBin)]
        // 잠금 회귀는 타이밍 승부라 1회 동시성으론 놓친다(수정 전 실측: 11/15 확률로 유실).
        // 20라운드 반복으로 유실 확률을 (1/2)^20 수준으로 눌러 결정적으로 검출한다.
        for round in 0..<20 {
            for (name, cli) in pairs {
                let caps = makeCaps(name: name, cli: round % 2 == 0 ? cli : cli + "-r\(round)")
                group.enter()
                Task.detached {
                    defer { group.leave() }
                    do {
                        _ = try store.upsert(caps)
                    } catch {
                        errors.append(String(describing: error))
                    }
                }
            }
            group.wait()
            #expect(errors.messages.isEmpty, "round \(round): \(errors.messages)")
            let apps = try store.load().apps
            #expect(apps["app-a"] != nil, "round \(round): app-a 유실 — 잠금이 스레드를 직렬화하지 못했다")
            #expect(apps["app-b"] != nil, "round \(round): app-b 유실 — 잠금이 스레드를 직렬화하지 못했다")
        }
    }

    @Test("실행 파일이 없으면 아무것도 지우지 않는다 — 애매하면 남긴다")
    func keepsEverythingWhenBinaryMissing() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) }
        let store = RegistryStore(fileURL: f.dir.appendingPathComponent("registry-store.json"))
        try store.upsert(makeCaps(name: "knowledge-base-wiki", cli: f.link))

        // 설치되지 않은 경로로 등록 — 같은 앱인지 판단할 근거가 없다.
        try store.upsert(makeCaps(name: "agent-wiki",
                                  cli: f.dir.appendingPathComponent("gone").path))
        #expect(try store.load().apps["knowledge-base-wiki"] != nil)
    }
}
