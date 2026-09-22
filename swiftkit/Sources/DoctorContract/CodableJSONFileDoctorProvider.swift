import Foundation

/// 파일이 있으면 JSON 디코드가 되어야 한다. 없는 첫 실행은 통과한다.
public struct CodableJSONFileDoctorProvider: DoctorProvider {
    public let id: String
    private let url: URL
    private let subject: String
    private let fileExists: @Sendable (String) -> Bool
    private let read: @Sendable (URL) throws -> Data
    private let decode: @Sendable (Data) throws -> Void

    public init<T: Decodable>(
        id: String,
        url: URL,
        as type: T.Type,
        subject: String,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .deferredToDate,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        read: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.id = id
        self.url = url
        self.subject = subject
        self.fileExists = fileExists
        self.read = read
        self.decode = { data in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = dateDecoding
            _ = try decoder.decode(T.self, from: data)
        }
    }

    public func run() async -> [DoctorFinding] {
        guard fileExists(url.path) else { return [] }
        let data: Data
        do {
            data = try read(url)
        } catch {
            return [finding(title: "도메인 JSON을 읽지 못했다", detail: "\(url.path): \(error.localizedDescription)")]
        }
        do {
            try decode(data)
            return []
        } catch {
            return [finding(title: "도메인 JSON이 깨져 있다", detail: "\(url.path): \(error.localizedDescription)")]
        }
    }

    private func finding(title: String, detail: String) -> DoctorFinding {
        DoctorFinding(
            category: .runtime,
            severity: .fail,
            body: .init(
                subject: subject,
                title: title,
                detail: detail,
                remedy: "원장을 고치거나 손상 파일을 치운 뒤 앱이 다시 쓰게 한다"
            ),
            source: id
        )
    }
}
