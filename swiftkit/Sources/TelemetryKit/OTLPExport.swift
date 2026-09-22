import Foundation
import EndpointRouterKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OTLP/HTTP JSON metrics 최소 인코더. 외부 SDK 없이 URLSession + JSONSerialization 만 쓴다.
public enum OTLPExport {
    /// 호스트는 EndpointRouterKit `otel` 키(원장 오버레이). 번들 폴백은 비어 있다.
    public static var defaultEndpoint: URL {
        EndpointRouter.joining(EndpointRouter.string("otel"), path: "v1/metrics")
            ?? URL(fileURLWithPath: "/invalid-otel")
    }

    public struct Metric {
        public let name: String
        public let description: String
        public let unit: String
        public let dataPoints: [DataPoint]

        public struct DataPoint {
            public let value: Double
            public let attributes: [String: String]

            public init(value: Double, attributes: [String: String] = [:]) {
                self.value = value
                self.attributes = attributes
            }
        }

        public init(name: String, description: String, unit: String = "1", dataPoints: [DataPoint]) {
            self.name = name
            self.description = description
            self.unit = unit
            self.dataPoints = dataPoints
        }
    }

    /// gauge 스냅샷 하나. 원장 집계는 누적이 아니라 지금 이 순간의 값이다.
    public static func payload(serviceName: String, metrics: [Metric], now: Date = Date()) -> [String: Any] {
        let nanos = String(Int64(now.timeIntervalSince1970 * 1_000_000_000))
        func attribute(_ key: String, _ value: String) -> [String: Any] {
            ["key": key, "value": ["stringValue": value]]
        }
        return [
            "resourceMetrics": [[
                "resource": ["attributes": [attribute("service.name", serviceName)]],
                "scopeMetrics": [[
                    "scope": ["name": serviceName],
                    "metrics": metrics.map { metric -> [String: Any] in
                        [
                            "name": metric.name,
                            "description": metric.description,
                            "unit": metric.unit,
                            "gauge": [
                                "dataPoints": metric.dataPoints.map { point -> [String: Any] in
                                    [
                                        "timeUnixNano": nanos,
                                        "asDouble": point.value,
                                        "attributes": point.attributes.sorted { $0.key < $1.key }
                                            .map { attribute($0.key, $0.value) },
                                    ]
                                },
                            ],
                        ]
                    },
                ]],
            ]],
        ]
    }

    public static func jsonData(_ payload: [String: Any], pretty: Bool = false) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: payload,
            options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        )
    }

    public struct SendResult {
        public let statusCode: Int?
        public let error: String?
        public var ok: Bool { error == nil && (200..<300).contains(statusCode ?? 0) }
    }

    /// 동기 전송. Foundation-only CLI 는 async main 을 쓰지 않는다.
    public static func send(_ payload: [String: Any], to endpoint: URL, timeout: TimeInterval = 10) -> SendResult {
        guard let body = try? jsonData(payload) else {
            return SendResult(statusCode: nil, error: "encode failed")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status: Int?
        nonisolated(unsafe) var errorText: String?
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error { errorText = error.localizedDescription }
            status = (response as? HTTPURLResponse)?.statusCode
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 2) == .timedOut {
            task.cancel()
            return SendResult(statusCode: nil, error: "timeout")
        }
        return SendResult(statusCode: status, error: errorText)
    }
}
