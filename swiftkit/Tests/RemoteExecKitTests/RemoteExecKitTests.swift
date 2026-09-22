import XCTest
import CommandKit
@testable import RemoteExecKit

private actor ScriptedCommandRunner: CommandRunning {
    struct Call: Sendable {
        let launchPath: String
        let arguments: [String]
        let timeout: TimeInterval?
    }

    private var results: [CommandResult]
    private var calls: [Call] = []

    init(_ results: [CommandResult]) {
        self.results = results
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        calls.append(Call(launchPath: launchPath, arguments: arguments, timeout: timeout))
        return results.removeFirst()
    }

    func recordedCalls() -> [Call] { calls }
}

final class RemoteExecKitTests: XCTestCase {
    func testSSHConfigParsesConcreteHosts() {
        let text = """
        Host prod jump
            HostName 10.0.0.1
            User root
            Port 2222
        Host *
            ForwardAgent yes
        """
        let hosts = SSHConfig.parse(text)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].alias, "prod")
        XCTAssertEqual(hosts[0].aliases, ["prod", "jump"])
        XCTAssertEqual(hosts[0].hostName, "10.0.0.1")
        XCTAssertEqual(hosts[0].user, "root")
        XCTAssertEqual(hosts[0].port, 2222)
        XCTAssertEqual(hosts[0].displayTarget, "root@10.0.0.1:2222")
    }

    func testManualCommandParsing() {
        XCTAssertEqual(SSHConfig.manualCommand("user@host"), ["ssh", "user@host"])
        XCTAssertEqual(SSHConfig.manualCommand("host:2200"), ["ssh", "-p", "2200", "host"])
        XCTAssertNil(SSHConfig.manualCommand("bad host"))
    }

    func testSSHAuthHeuristic() {
        XCTAssertTrue(SSHAuth.isAuthFailure("Permission denied (publickey)."))
        XCTAssertTrue(SSHAuth.isAuthFailure("Host key verification failed."))
        XCTAssertFalse(SSHAuth.isAuthFailure("Connection timed out"))
    }

    func testSystemSSHClientMapsExitCodeToError() async {
        // 존재하지 않는 host — ssh 는 비영으로 종료. 실제 실행하되 결과가 실패 케이스인지만 확인.
        let client = SystemSSHClient(connectTimeout: 1)
        let result = await client.run(host: "203.0.113.1", user: "nobody", port: 22, command: "true")
        if case .success = result { XCTFail("expected failure for unreachable host") }
    }

    func testSystemSSHClientUsesDeterministicPrivateControlSocket() async throws {
        let process = ScriptedCommandRunner([
            CommandResult(stdout: "ok\n", stderr: "", exitCode: 0),
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-exec-control-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = SystemSSHClient(
            connectTimeout: 8,
            controlMaster: SSHControlMasterConfiguration(
                controlDirectory: directory,
                persistSeconds: 60
            ),
            runner: process
        )

        let result = await client.run(
            host: "pve.example",
            user: "root",
            port: 2222,
            command: "hostname",
            timeout: 12
        )

        XCTAssertEqual(try? result.get(), "ok\n")
        let calls = await process.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].launchPath, "/usr/bin/ssh")
        XCTAssertEqual(calls[0].timeout, 12)
        XCTAssertTrue(calls[0].arguments.contains("ControlMaster=auto"))
        XCTAssertTrue(calls[0].arguments.contains("ControlPersist=60"))
        let socketName = SSHControlMasterConfiguration.controlSocketName(
            user: "root",
            host: "pve.example",
            port: 2222
        )
        XCTAssertTrue(calls[0].arguments.contains("ControlPath=\(directory.path)/\(socketName)"))
        XCTAssertEqual(Array(calls[0].arguments.suffix(2)), ["root@pve.example", "hostname"])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testSystemSSHClientRemovesStaleSocketAndRetriesOnce() async throws {
        let process = ScriptedCommandRunner([
            CommandResult(
                stdout: "",
                stderr: "Control socket connect(/tmp/example): Connection refused",
                exitCode: 255
            ),
            CommandResult(stdout: "recovered", stderr: "", exitCode: 0),
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-exec-stale-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controlMaster = SSHControlMasterConfiguration(controlDirectory: directory)
        let socket = controlMaster.controlSocketURL(user: "root", host: "pve.example", port: 22)
        try Data("stale".utf8).write(to: socket)
        let client = SystemSSHClient(controlMaster: controlMaster, runner: process)

        let result = await client.run(host: "pve.example", user: "root", port: 22, command: "hostname")

        XCTAssertEqual(try? result.get(), "recovered")
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket.path))
        let calls = await process.recordedCalls()
        XCTAssertEqual(calls.count, 2)
    }

    func testSystemSSHClientRejectsUnsafeControlDirectoryPath() async throws {
        let process = ScriptedCommandRunner([
            CommandResult(stdout: "unexpected", stderr: "", exitCode: 0),
        ])
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-exec-unsafe-test-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let client = SystemSSHClient(
            controlMaster: SSHControlMasterConfiguration(controlDirectory: path),
            runner: process
        )

        let result = await client.run(host: "pve.example", user: "root", port: 22, command: "hostname")

        guard case .failure(.commandFailed(let message)) = result else {
            return XCTFail("expected unsafe control directory failure")
        }
        XCTAssertTrue(message.contains("not a user-owned directory"))
        let calls = await process.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }
}
