import EndpointRouterKit
import Foundation

/// wiki-hub 원격 질의 — 로컬 world 없이도 원장을 검색한다.
/// 호스트는 env `GUJO_HUB_URL`, 있으면 EndpointRouterKit `wiki-hub`. 소스에 클러스터 DNS 를 박지 않는다.
///
/// 서버 응답은 `fleet pull --json`(FleetPullResult) 계약 그대로다. 여기서 같은
/// Codable 타입으로 **디코드하는 것 자체가 살아있는 계약 검증**이다 — 서버가
/// 스키마를 어기면 이 클라이언트가 즉시 깨진다(파서 이원화 없음).
public struct GujoHubClient: Sendable {
    public static var defaultBaseURL: URL? {
        let env = ProcessInfo.processInfo.environment["GUJO_HUB_URL"] ?? ""
        if !env.isEmpty { return URL(string: env) }
        let ledger = EndpointRouter.string("wiki-hub")
        if !ledger.isEmpty { return URL(string: ledger) }
        return nil
    }

    public let baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    /// env `GUJO_HUB_URL` 우선(테스트·비상 우회), 그다음 EndpointRouterKit `wiki-hub`.
    public static func fromEnvironment() -> GujoHubClient {
        GujoHubClient(baseURL: defaultBaseURL ?? URL(fileURLWithPath: "/invalid-wiki-hub"))
    }

    public func search(query: String, limit: Int? = nil, bodyChars: Int? = nil)
        -> Result<(result: FleetPullResult, raw: Data), GujoError> {
        var items = [URLQueryItem(name: "q", value: query)]
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let bodyChars { items.append(URLQueryItem(name: "bodyChars", value: String(bodyChars))) }
        return get(path: "/search", queryItems: items)
    }

    public func object(id: String, bodyChars: Int? = nil)
        -> Result<(result: FleetPullResult, raw: Data), GujoError> {
        var items: [URLQueryItem] = []
        if let bodyChars { items.append(URLQueryItem(name: "bodyChars", value: String(bodyChars))) }
        return get(path: "/objects/\(id)", queryItems: items)
    }

    func get(path: String, queryItems: [URLQueryItem])
        -> Result<(result: FleetPullResult, raw: Data), GujoError> {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return .failure(.refused("hub URL 이 이상하다: \(baseURL)")) }
        components.path = path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { return .failure(.refused("URL 조립 실패")) }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<(result: FleetPullResult, raw: Data), GujoError> =
            .failure(.unreachable("응답 없음"))
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failure(.unreachable("hub 도달 실패: \(error.localizedDescription) — VPN/내부망 확인"))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                outcome = .failure(.unreachable("HTTP 응답 아님"))
                return
            }
            guard http.statusCode == 200 || http.statusCode == 404 else {
                outcome = .failure(.git("hub \(http.statusCode): \(String(decoding: data.prefix(200), as: UTF8.self))"))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(FleetPullResult.self, from: data)
                outcome = .success((decoded, data))
            } catch {
                outcome = .failure(.git("FleetPullResult 계약 위반 응답: \(error)"))
            }
        }.resume()
        semaphore.wait()
        return outcome
    }
}
