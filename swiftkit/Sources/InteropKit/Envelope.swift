import Foundation

// 앱 상호운용 계약(docs/app-interop-contract.md)의 봉투:
// 성공 {"ok": true, "result": ...} / 실패 {"ok": false, "error": {"message": "..."}}.
// orca 형식을 표준으로 채택했으므로 키 이름·구조를 임의로 바꾸지 않는다.
public enum Envelope {
    // MARK: - Codable 제네릭 경로 (타입이 정해진 소비자용)

    /// 성공 봉투. `result` 타입이 Codable 이면 그대로 감싼다.
    public struct Success<Result: Codable>: Codable {
        public let ok: Bool
        public let result: Result

        public init(result: Result) {
            self.ok = true
            self.result = result
        }
    }

    /// 실패 봉투. 계약상 error 는 최소 message 를 가진 객체다.
    public struct Failure: Codable {
        public struct ErrorBody: Codable {
            public let message: String
            public init(message: String) { self.message = message }
        }

        public let ok: Bool
        public let error: ErrorBody

        public init(message: String) {
            self.ok = false
            self.error = ErrorBody(message: message)
        }
    }

    /// 성공 봉투 JSON 데이터 생성.
    public static func ok<Result: Codable>(_ result: Result) throws -> Data {
        try encoder().encode(Success(result: result))
    }

    /// 실패 봉투 JSON 데이터 생성.
    public static func fail(_ message: String) throws -> Data {
        try encoder().encode(Failure(message: message))
    }

    /// 봉투 파싱: ok=true 면 result 를 디코드, ok=false 면 error.message 를 던진다.
    /// 소비자가 분기 코드를 반복하지 않도록 실패를 Swift 에러로 승격한다.
    public static func decodeResult<Result: Codable>(
        _ type: Result.Type, from data: Data
    ) throws -> Result {
        let decoder = JSONDecoder()
        do {
            let success = try decoder.decode(Success<Result>.self, from: data)
            if success.ok {
                return success.result
            }
        } catch {}
        do {
            let failure = try decoder.decode(Failure.self, from: data)
            if !failure.ok {
                throw EnvelopeError.remote(message: failure.error.message)
            }
        } catch let err as EnvelopeError {
            throw err
        } catch {}
        throw EnvelopeError.malformed
    }

    // MARK: - JSONSerialization 경로 (타입 없는 dictionary 소비자용)

    /// 임의 JSON 객체를 성공 봉투로 감싼다. CLI 가 이미 [String: Any] 를 들고 있을 때.
    public static func okObject(_ result: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["ok": true, "result": result],
            options: [.sortedKeys]
        )
    }

    /// 실패 봉투 JSON. JSONSerialization 경로.
    public static func failObject(_ message: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["ok": false, "error": ["message": message]],
            options: [.sortedKeys]
        )
    }

    /// JSONSerialization 로 봉투를 파싱. 성공이면 result(Any), 실패면 에러 승격.
    public static func parseObject(_ data: Data) throws -> Any {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool
        else { throw EnvelopeError.malformed }
        if ok {
            guard let result = object["result"] else { throw EnvelopeError.malformed }
            return result
        }
        let message = (object["error"] as? [String: Any])?["message"] as? String
        throw EnvelopeError.remote(message: message ?? "unknown error")
    }

    // 봉투는 사람도 diff 로 읽으므로 키 정렬을 고정해 출력 안정성을 확보한다.
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public enum EnvelopeError: Error, Equatable, LocalizedError {
    /// ok=false 봉투 — 상대 앱이 보고한 실패.
    case remote(message: String)
    /// 봉투 구조 자체가 계약과 다름.
    case malformed

    public var errorDescription: String? {
        switch self {
        case .remote(let message): return message
        case .malformed: return "malformed interop envelope"
        }
    }
}
