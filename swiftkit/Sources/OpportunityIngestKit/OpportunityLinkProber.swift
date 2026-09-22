import Foundation
import HTTPClientKit
import WebCrawlKit
import OpportunityIntelKit

/// 비동기 링크 생존 상태 프로브 엔진 (Swift Concurrency 기반)
/// DispatchSemaphore 동기 블로킹 없이 TaskGroup을 사용하여 대규모 링크를 신속하게 검사
public enum OpportunityLinkProber {

    public struct ProbeResult: Sendable, Equatable {
        public var url: String
        public var statusCode: Int?
        public var isAlive: Bool
        public var liveness: OpportunityLiveness
        public var finalURL: String?

        public init(
            url: String,
            statusCode: Int?,
            isAlive: Bool,
            liveness: OpportunityLiveness,
            finalURL: String? = nil
        ) {
            self.url = url
            self.statusCode = statusCode
            self.isAlive = isAlive
            self.liveness = liveness
            self.finalURL = finalURL
        }
    }

    public static let defaultProbeTimeoutSeconds: TimeInterval = 10

    /// 단일 URL 생존 여부 비동기 검사 (HEAD 우선, 실패 시 GET 폴백)
    public static func probe(
        urlString: String,
        timeout: TimeInterval = defaultProbeTimeoutSeconds,
        client: any HTTPClient = URLSessionHTTPClient()
    ) async -> ProbeResult {
        guard let url = URL(string: urlString) else {
            return ProbeResult(url: urlString, statusCode: nil, isAlive: false, liveness: .dead)
        }

        var headers = WebFetch.standardBrowserHeaders
        headers["Range"] = "bytes=0-1024" // 본문 최소 수신

        do {
            // 1. HEAD 요청 시도
            let (headStatus, _) = try await client.send(method: "HEAD", url: url, headers: headers, body: nil)
            if (200..<400).contains(headStatus) {
                return ProbeResult(url: urlString, statusCode: headStatus, isAlive: true, liveness: .alive)
            }
            if headStatus == 404 || headStatus == 410 {
                return ProbeResult(url: urlString, statusCode: headStatus, isAlive: false, liveness: .dead)
            }
        } catch {
            FileHandle.standardError.write(Data("[OpportunityLinkProber] HEAD failed for \(url), falling back to GET: \(error)\n".utf8))
        }

        do {
            // 2. GET 요청 폴백
            let (getStatus, _) = try await client.send(method: "GET", url: url, headers: headers, body: nil)
            let alive = (200..<400).contains(getStatus)
            let liveness: OpportunityLiveness = alive ? .alive : ((getStatus == 404 || getStatus == 410) ? .dead : .caution)
            return ProbeResult(url: urlString, statusCode: getStatus, isAlive: alive, liveness: liveness)
        } catch {
            return ProbeResult(url: urlString, statusCode: nil, isAlive: false, liveness: .caution)
        }
    }

    /// 여러 URL을 동시성 제한 하에 병렬 검사
    public static func probeBatch(
        urls: [String],
        maxConcurrency: Int = 6,
        timeout: TimeInterval = defaultProbeTimeoutSeconds,
        client: any HTTPClient = URLSessionHTTPClient()
    ) async -> [String: ProbeResult] {
        await withTaskGroup(of: (String, ProbeResult).self) { group in
            var iterator = urls.makeIterator()
            var results: [String: ProbeResult] = [:]

            // 초기 동시 실행 작업 채우기
            for _ in 0..<maxConcurrency {
                if let nextURL = iterator.next() {
                    group.addTask {
                        let res = await probe(urlString: nextURL, timeout: timeout, client: client)
                        return (nextURL, res)
                    }
                }
            }

            // 완료될 때마다 다음 작업 추가 (동시성 제한 유지)
            for await (url, res) in group {
                results[url] = res
                if let nextURL = iterator.next() {
                    group.addTask {
                        let nextRes = await probe(urlString: nextURL, timeout: timeout, client: client)
                        return (nextURL, nextRes)
                    }
                }
            }

            return results
        }
    }
}
