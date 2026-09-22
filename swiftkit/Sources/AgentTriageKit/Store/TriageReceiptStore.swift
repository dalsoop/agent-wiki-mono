import Foundation
import StateRootKit

public actor TriageReceiptStore {
    public static let shared = TriageReceiptStore()

    private let storeURL: URL

    public init(customDirectory: URL? = nil) {
        if let custom = customDirectory {
            self.storeURL = custom.appendingPathComponent("triage-receipts.jsonl")
        } else {
            let opsDir = StateRootKit.url("triage-receipts")
            // ops 디렉터리 생성 (기존에 존재하면 무시)
            do {
                try FileManager.default.createDirectory(at: opsDir, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(Data("[AgentTriageKit] Failed to create directory: \(error)\n".utf8))
            }
            self.storeURL = opsDir.appendingPathComponent("triage-receipts.jsonl")
        }
    }

    public func append(_ receipt: TriageReceipt) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")

        if FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: storeURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let lineData = line.data(using: .utf8) {
                    handle.write(lineData)
                }
            } catch {
                // 파일 핸들 열기 실패 시 원자적 덮어쓰기로 폴백
                try line.write(to: storeURL, atomically: true, encoding: .utf8)
            }
        } else {
            try line.write(to: storeURL, atomically: true, encoding: .utf8)
        }
    }

    public func loadAll() -> [TriageReceipt] {
        do {
            let content = try String(contentsOf: storeURL, encoding: .utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return content.split(separator: "\n").compactMap { line -> TriageReceipt? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(TriageReceipt.self, from: data)
            }
        } catch {
            return []
        }
    }

    public func markRevived(id: UUID) {
        var all = loadAll()
        for i in 0..<all.count {
            if all[i].id == id {
                all[i].isRevived = true
                all[i].revivedAt = Date()
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var newLines = ""
        for r in all {
            do {
                let data = try encoder.encode(r)
                if let str = String(data: data, encoding: .utf8) {
                    newLines.append(str + "\n")
                }
            } catch {
                FileHandle.standardError.write(Data("[AgentTriageKit] Failed to encode receipt: \(error)\n".utf8))
            }
        }
        do {
            try newLines.write(to: storeURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("[AgentTriageKit] Failed to write receipts: \(error)\n".utf8))
        }
    }
}
