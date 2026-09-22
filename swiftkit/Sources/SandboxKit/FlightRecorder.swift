import Foundation

/// 룸 샌드박스 내부에서 일어난 모든 도구 실행, 입출력, 상태 변화를 기록하는 비행 기록(Flight Record) 모델.
public struct FlightRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String { recordID }
    public let recordID: String
    public let roomID: String
    public let tenant: String
    public let agentID: String?
    public let stepIndex: Int
    public let timestamp: Date
    public let executable: String
    public let arguments: [String]
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Double
    public let fileDeltas: [String]

    public init(
        recordID: String = UUID().uuidString,
        roomID: String,
        tenant: String,
        agentID: String? = nil,
        stepIndex: Int,
        timestamp: Date = Date(),
        executable: String,
        arguments: [String],
        exitCode: Int32,
        stdout: String,
        stderr: String,
        durationMs: Double,
        fileDeltas: [String] = []
    ) {
        self.recordID = recordID
        self.roomID = roomID
        self.tenant = tenant
        self.agentID = agentID
        self.stepIndex = stepIndex
        self.timestamp = timestamp
        self.executable = executable
        self.arguments = arguments
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
        self.fileDeltas = fileDeltas
    }
}

/// 룸 샌드박스 비행 기록 장치 (AI Flight Recorder & Time-Travel Replay Engine).
public enum FlightRecorder {
    public static let recordFileName = ".flight_recorder.jsonl"

    /// 실행 이벤트를 룸 내부 비행 기록 파일에 추가 기록한다.
    public static func record(
        event: FlightRecord,
        context: SandboxContext
    ) throws {
        let recordFileURL = context.sandboxDirectory.appendingPathComponent(recordFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var data = try encoder.encode(event)
        data.append(contentsOf: "\n".utf8)

        let fm = FileManager.default
        if fm.fileExists(atPath: recordFileURL.path) {
            let handle = try FileHandle(forWritingTo: recordFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: recordFileURL, options: .atomic)
        }
    }

    /// 룸 내부의 모든 비행 기록을 순서대로 읽어온다. 파일이 없으면 빈 배열.
    public static func readHistory(context: SandboxContext) throws -> [FlightRecord] {
        let recordFileURL = context.sandboxDirectory.appendingPathComponent(recordFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: recordFileURL.path) else { return [] }

        let data: Data
        do {
            data = try Data(contentsOf: recordFileURL)
        } catch {
            throw FlightRecorderError.unreadable(recordFileURL, error)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw FlightRecorderError.invalidEncoding(recordFileURL)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records: [FlightRecord] = []
        for (index, line) in content.split(separator: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let lineData = trimmed.data(using: .utf8) else {
                throw FlightRecorderError.malformedLine(index + 1, nil)
            }
            do {
                records.append(try decoder.decode(FlightRecord.self, from: lineData))
            } catch {
                throw FlightRecorderError.malformedLine(index + 1, error)
            }
        }
        return records.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// 특정 스텝까지의 캐시된 결과로 복원(Time-Travel)하여 실패 지점 이전 상태를 재현한다.
    public static func replay(
        upToStep: Int,
        context: SandboxContext
    ) throws -> [FlightRecord] {
        let history = try readHistory(context: context)
        return history.filter { $0.stepIndex <= upToStep }
    }
}

public enum FlightRecorderError: Error, LocalizedError {
    case unreadable(URL, Error)
    case invalidEncoding(URL)
    case malformedLine(Int, Error?)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let error):
            return "비행 기록을 읽을 수 없습니다 (\(url.path)): \(error.localizedDescription)"
        case .invalidEncoding(let url):
            return "비행 기록이 UTF-8 이 아닙니다: \(url.path)"
        case .malformedLine(let line, let error):
            let detail = error.map { $0.localizedDescription } ?? "invalid utf-8"
            return "비행 기록 \(line)번째 줄이 깨졌습니다: \(detail)"
        }
    }
}
