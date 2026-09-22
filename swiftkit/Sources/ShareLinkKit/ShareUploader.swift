import Foundation

/// 실제로 올리고 공유 주소를 돌려준다.
///
/// 요청 조립·서명은 `ShareRequestBuilder` 가 하고 여기서는 보내기만 한다 —
/// 그래야 틀리기 쉬운 부분이 전부 테스트 대상으로 남는다.
public struct ShareUploader: Sendable {

    /// 전송 seam. 테스트는 네트워크 없이 응답을 흉내 낸다.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum UploadError: Error, LocalizedError {
        case missingCredential(profile: String)
        case rejected(status: Int, body: String)
        case transport(any Error)

        public var errorDescription: String? {
            switch self {
            case .missingCredential(let profile):
                return "'\(profile)' 카드에 접근키가 없다 — 설정에서 카드를 채워라"
            case .rejected(let status, let body):
                // 저장소는 이유를 본문에 담아 보낸다. 상태 코드만 보여 주면
                // "403" 만 남아서 버킷 권한인지 서명 문제인지 알 수 없다.
                let detail = body.isEmpty ? "" : " — \(body.prefix(300))"
                return "저장소가 거절했다(HTTP \(status))\(detail)"
            case .transport(let error):
                return "저장소에 닿지 못했다: \(error.localizedDescription)"
            }
        }
    }

    private let transport: Transport

    public init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.transport = transport
    }

    /// 데이터를 올리고 공유 주소를 돌려준다.
    ///
    /// - Parameters:
    ///   - credentials: 카드에서 꺼낸 값. `ShareCredential.keys(from:)` 로 검증해 넘긴다.
    ///   - date: 서명 시각. 테스트가 고정할 수 있게 인자로 받는다.
    public func upload(
        _ data: Data,
        contentType: String,
        fileExtension: String,
        target: ShareTarget,
        credentials: [String: String],
        date: Date = Date(),
        cacheSeconds: Int? = 31_536_000
    ) async throws -> URL {
        guard let keys = ShareCredential.keys(from: credentials) else {
            throw UploadError.missingCredential(profile: target.credentialProfile)
        }
        let objectKey = ShareObjectKey.make(
            prefix: target.pathPrefix, fileExtension: fileExtension, date: date
        )
        let request = try ShareRequestBuilder.uploadRequest(
            target: target, objectKey: objectKey, body: data, contentType: contentType,
            accessKey: keys.access, secretKey: keys.secret, date: date,
            cacheSeconds: cacheSeconds
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw UploadError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError.rejected(
                status: status, body: String(decoding: data, as: UTF8.self)
            )
        }
        return try ShareRequestBuilder.shareURL(
            target: target, objectKey: objectKey,
            accessKey: keys.access, secretKey: keys.secret, date: date
        )
    }
}
