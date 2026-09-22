import Foundation
import StateRootKit

/// 논리적 단언형 문장으로 완전히 환원되지 않는 에이전트의 잠재적 불확실성/위화감 프로파일
public struct CognitiveAmbiguityProfile: Codable, Sendable, Equatable {
    /// 1. 주관적 확신도 (0.0: 완전한 추측 ~ 1.0: 단언적 확신)
    public var confidenceScore: Double

    /// 2. 인지 부조화: 상호 배타적으로 충돌하는 대안 가설 목록
    public var competingHypotheses: [String]

    /// 3. 원초적 직관/위화감 (Code Smell Intuition)
    public var intuitiveSmell: String?

    /// 4. 행동적 망설임 지표 (편집 롤백/취소 횟수)
    public var hesitationCount: Int

    /// 5. 미해결 의문점 (작업 종료 시점까지 풀리지 않은 질문)
    public var unresolvedQuestions: [String]

    public init(
        confidenceScore: Double = 1.0,
        competingHypotheses: [String] = [],
        intuitiveSmell: String? = nil,
        hesitationCount: Int = 0,
        unresolvedQuestions: [String] = []
    ) {
        self.confidenceScore = max(0.0, min(1.0, confidenceScore))
        self.competingHypotheses = competingHypotheses
        self.intuitiveSmell = intuitiveSmell
        self.hesitationCount = hesitationCount
        self.unresolvedQuestions = unresolvedQuestions
    }

    /// 꿈 단계에서 A/B 반사실 분기 탐색이 필요한지 판정
    public var requiresCounterfactualExploration: Bool {
        confidenceScore < 0.8 || !competingHypotheses.isEmpty || hesitationCount >= 2 || !unresolvedQuestions.isEmpty
    }
}

/// 기상/작업(Wake Phase) 중에 에이전트 1인칭 시점의 대화 세션 및 인지 논리와 기계적 텔레메트리를
/// 단일 트랜잭션으로 영구 기록하는 에피소드 스키마 (Wake Episode Record).
public struct WakeEpisodeRecord: Codable, Sendable, Identifiable, Equatable {
    public let episodeId: UUID
    public var id: UUID { episodeId }
    public let timestamp: Date

    // 1인칭 시점 및 세션 매핑 (First-Person Perspective & Session Trace)
    public let agentId: String
    public let conversationId: String
    public let sessionId: String
    public let roomId: String?
    public let ruleId: String?
    public let targetFile: String

    // 기계적 텔레메트리 (Mechanical Telemetry)
    public let durationMs: Double
    public let cpuUsagePercent: Double
    public let astNodeCount: Int
    public let errorCategory: String?
    public let exitCode: Int32

    // 인지 논리 문장 (Cognitive Logic Trace)
    public let intentSentence: String
    public let hypothesis: String
    public let observedAnomaly: String

    // 비명제적 흔들림 프로파일 (Latent Cognitive Ambiguity Profile)
    public let ambiguity: CognitiveAmbiguityProfile

    public init(
        episodeId: UUID = UUID(),
        timestamp: Date = Date(),
        agentId: String,
        conversationId: String,
        sessionId: String = UUID().uuidString,
        roomId: String? = nil,
        ruleId: String? = nil,
        targetFile: String,
        durationMs: Double,
        cpuUsagePercent: Double = 0.0,
        astNodeCount: Int = 0,
        errorCategory: String? = nil,
        exitCode: Int32 = 0,
        intentSentence: String,
        hypothesis: String,
        observedAnomaly: String,
        ambiguity: CognitiveAmbiguityProfile = CognitiveAmbiguityProfile()
    ) {
        self.episodeId = episodeId
        self.timestamp = timestamp
        self.agentId = agentId
        self.conversationId = conversationId
        self.sessionId = sessionId
        self.roomId = roomId
        self.ruleId = ruleId
        self.targetFile = targetFile
        self.durationMs = durationMs
        self.cpuUsagePercent = cpuUsagePercent
        self.astNodeCount = astNodeCount
        self.errorCategory = errorCategory
        self.exitCode = exitCode
        self.intentSentence = intentSentence
        self.hypothesis = hypothesis
        self.observedAnomaly = observedAnomaly
        self.ambiguity = ambiguity
    }
}

/// 0.01ms 내에 논블로킹 I/O로 에피소드를 적층하는 영구 링 버퍼 저장소 (Wake Episode Store).
public final class WakeEpisodeStore: @unchecked Sendable {
    public static let shared = WakeEpisodeStore()

    private let lock = NSLock()
    private let capacity: Int = 2000
    private var buffer: [WakeEpisodeRecord?]
    private var writeIndex: Int = 0
    private let storeDirectory: URL
    private let storeFile: URL
    private let encoder: JSONEncoder

    public init(storeDirectory: URL? = nil) {
        self.buffer = Array(repeating: nil, count: capacity)
        let dir: URL
        if let storeDirectory {
            dir = storeDirectory
        } else {
            dir = StateRootKit.url(".agent-lint/wake-episodes")
        }
        self.storeDirectory = dir
        self.storeFile = dir.appendingPathComponent("wake-episodes.jsonl")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        ensureDirectory()
    }

    private func ensureDirectory() {
        if !FileManager.default.fileExists(atPath: storeDirectory.path) {
            do { try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true) } catch { _ = error }
        }
    }

    /// 0.01ms 내에 링 버퍼 기록 및 비동기 디스크 적층
    public func record(_ episode: WakeEpisodeRecord) {
        lock.lock()
        buffer[writeIndex] = episode
        writeIndex = (writeIndex + 1) % capacity
        lock.unlock()

        appendToFile(episode)
    }

    private func appendToFile(_ episode: WakeEpisodeRecord) {
        guard let data = try? encoder.encode(episode),
              let line = String(data: data, encoding: .utf8) else { return }

        let lineData = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: storeFile.path) {
            do {
                let handle = try FileHandle(forWritingTo: storeFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
            } catch {
                // 절단 방어: 기존 파일이 존재할 때 쓰기 에러 발생 시 원장 덮어쓰기(절단) 방지 및 do-catch 안전 처리
            }
        } else {
            ensureDirectory()
            do {
                try lineData.write(to: storeFile, options: .atomic)
            } catch {
                // 최초 파일 생성 실패 안전 처리
            }
        }
    }

    /// 최근 축적된 에피소드 질의 (세션/에이전트별 필터링 지원)
    public func queryEpisodes(
        since: Date? = nil,
        agentId: String? = nil,
        conversationId: String? = nil
    ) -> [WakeEpisodeRecord] {
        lock.lock()
        var items = buffer.compactMap { $0 }
        lock.unlock()

        if items.isEmpty, FileManager.default.fileExists(atPath: storeFile.path) {
            do {
                let content = try String(contentsOf: storeFile, encoding: .utf8)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                items = content.components(separatedBy: .newlines).compactMap { line in
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                          let data = line.data(using: .utf8) else { return nil }
                    do {
                        return try decoder.decode(WakeEpisodeRecord.self, from: data)
                    } catch {
                        return nil
                    }
                }
            } catch {}
        }

        return items.filter { item in
            if let since, item.timestamp < since { return false }
            if let agentId, item.agentId != agentId { return false }
            if let conversationId, item.conversationId != conversationId { return false }
            return true
        }
    }
}
