import CommandKit
import MoneyLedgerStoreKit
import MoneyLedgerModels
import Foundation
import InteropKit

/// 금고 창구 — **우리 Vaultwarden Client 앱의 CLI**에 서류·비밀을 맡긴다.
/// 앱이 로그인·암호화를 소유하므로 장부 앱은 별도 로그인도, 외부 도구(bw)도 필요 없다
/// (소유 앱 CLI 우선 계약: docs/app-interop-contract.md).
public struct VaultDocsGateway: Sendable {
    public enum Status: String, Codable, Sendable {
        /// 앱 로그인 + 잠금해제 — 모든 작업 가능.
        case ready
        /// 로그인은 됐지만 잠김 — 앱을 열거나 Touch ID 로 해제.
        case locked
        /// 앱에 로그인한 적 없음.
        case notLoggedIn
        /// vaultwarden-client CLI 를 찾지 못함(앱 미설치).
        case unavailable

        public var korean: String {
            switch self {
            case .ready: "준비됨"
            case .locked: "잠김 — Vaultwarden Client 앱에서 잠금해제하세요"
            case .notLoggedIn: "미로그인 — Vaultwarden Client 앱에서 로그인하세요"
            case .unavailable: "Vaultwarden Client 앱이 없습니다"
            }
        }
    }

    public struct DocumentFile: Sendable, Equatable, Identifiable {
        public let id: String
        public let fileName: String
        public let sizeName: String

        public init(id: String, fileName: String, sizeName: String) {
            self.id = id
            self.fileName = fileName
            self.sizeName = sizeName
        }
    }

    private let runner: CommandRunning
    private let cliPath: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        cliPath: String = HostPlatform.cliBinPath("vaultwarden-client")
    ) {
        self.runner = runner
        self.cliPath = cliPath
    }

    // MARK: - 상태

    public func status() async -> Status {
        let result = await run(["status", "--json"])
        guard let payload = result.payload else { return .unavailable }
        switch payload["status"] as? String {
        case "ready": return .ready
        case "locked": return .locked
        case "notLoggedIn": return .notLoggedIn
        default: return .unavailable
        }
    }

    // MARK: - 서류(파일)

    public func upload(fileURL: URL, box: String) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultDocsError.fileMissing(fileURL.path)
        }
        let result = await run(["docs", "upload", box, fileURL.path, "--json"])
        guard result.ok else { throw VaultDocsError.failed("업로드", result.message) }
    }

    public func list(box: String) async throws -> [DocumentFile] {
        let result = await run(["docs", "list", box, "--json"])
        guard result.ok, let payload = result.payload else {
            throw VaultDocsError.failed("목록", result.message)
        }
        return (payload["attachments"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["fileName"] as? String else { return nil }
            return DocumentFile(id: id, fileName: name, sizeName: entry["sizeName"] as? String ?? "")
        }
    }

    public func download(file: DocumentFile, box: String, to outputURL: URL) async throws {
        let result = await run(["docs", "download", box, file.id, "--out", outputURL.path, "--json"])
        guard result.ok else { throw VaultDocsError.failed("내려받기", result.message) }
    }

    public func delete(file: DocumentFile, box: String) async throws {
        let result = await run(["docs", "delete", box, file.id, "--json"])
        guard result.ok else { throw VaultDocsError.failed("삭제", result.message) }
    }

    // MARK: - 텍스트 비밀(카드·계좌번호)

    public func setNote(name: String, text: String) async throws {
        let result = await runWithInput(["note", "set", name, "--json"], input: text)
        guard result.ok else { throw VaultDocsError.failed("비밀 저장", result.message) }
    }

    public func note(name: String) async throws -> String? {
        let result = await run(["note", "get", name, "--json"])
        guard result.ok, let payload = result.payload else { return nil }
        return payload["value"] as? String
    }

    @discardableResult
    public func deleteNote(name: String) async throws -> Bool {
        let result = await run(["note", "rm", name, "--json"])
        guard result.ok, let payload = result.payload else { return false }
        return payload["removed"] as? Bool ?? true
    }

    // MARK: - 내부

    private struct Reply {
        let ok: Bool
        let payload: [String: Any]?
        let message: String
    }

    private func run(_ arguments: [String]) async -> Reply {
        let result = await runner.run(cliPath, arguments, timeout: 120)
        return parse(result.trimmedStdout, ok: result.ok)
    }

    /// stdin 으로 비밀값을 넘긴다 — argv 에 남기지 않는다.
    /// 상대가 매달리면 호출측이 영원히 멈추므로 워치독으로 끊고, 파이프는 **대기 전에** 드레인한다.
    private func runWithInput(
        _ arguments: [String], input: String, timeout: TimeInterval = 120
    ) async -> Reply {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            return Reply(ok: false, payload: nil, message: String(describing: error))
        }
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        try? inputPipe.fileHandleForWriting.close()

        let watchdog = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // 파이프 버퍼가 차면 상대가 write 에서 멈추므로 대기 전에 읽어 비운다.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationReason == .uncaughtSignal, output.isEmpty {
            return Reply(ok: false, payload: nil, message: "금고 앱 응답이 \(Int(timeout))초 내에 없었습니다")
        }
        return parse(output, ok: process.terminationStatus == 0)
    }

    private func parse(_ output: String, ok: Bool) -> Reply {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let data = String(output[start...end]).data(using: .utf8) else {
            return Reply(ok: false, payload: nil, message: output.isEmpty ? "응답 없음" : output)
        }
        let object: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Reply(ok: false, payload: nil, message: output.isEmpty ? "응답 없음" : output)
            }
            object = obj
        } catch {
            return Reply(ok: false, payload: nil, message: output.isEmpty ? "응답 없음" : output)
        }
        if object["ok"] as? Bool == true {
            return Reply(ok: true, payload: object["result"] as? [String: Any] ?? [:], message: "")
        }
        let message = (object["error"] as? [String: Any])?["message"] as? String ?? output
        return Reply(ok: false, payload: nil, message: message)
    }
}

public enum VaultDocsError: Error, Equatable, CustomStringConvertible {
    case fileMissing(String)
    case failed(String, String)

    public var description: String {
        switch self {
        case let .fileMissing(path): "파일이 없습니다: \(path)"
        case let .failed(operation, detail): "금고 \(operation) 실패: \(String(detail.prefix(200)))"
        }
    }
}
