import Foundation
import EndpointRouterKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 구조 위성 사이트 품질 및 거버넌스 감사기 (0~100점 점수화 엔진)
public struct FleetAuditor: Sendable {

    public struct CheckItem: Sendable, Codable {
        public let name: String
        public let maxScore: Int
        public let score: Int
        public let passed: Bool
        public let details: String

        public init(name: String, maxScore: Int, score: Int, passed: Bool, details: String) {
            self.name = name
            self.maxScore = maxScore
            self.score = score
            self.passed = passed
            self.details = details
        }
    }

    public struct SiteAuditResult: Sendable, Codable {
        public let domain: String
        public let url: String
        public let httpStatus: Int
        public let score: Int
        public let passed: Bool
        public let checks: [CheckItem]
        public let issues: [String]

        public init(domain: String, url: String, httpStatus: Int, score: Int, passed: Bool, checks: [CheckItem], issues: [String]) {
            self.domain = domain
            self.url = url
            self.httpStatus = httpStatus
            self.score = score
            self.passed = passed
            self.checks = checks
            self.issues = issues
        }
    }

    public struct FleetReport: Sendable, Codable {
        public let timestamp: String
        public let averageScore: Double
        public let allPassed: Bool
        public let sites: [SiteAuditResult]

        public init(timestamp: String, averageScore: Double, allPassed: Bool, sites: [SiteAuditResult]) {
            self.timestamp = timestamp
            self.averageScore = averageScore
            self.allPassed = allPassed
            self.sites = sites
        }
    }

    public static var targetDomains: [(name: String, url: String)] {
        let endpoints: [(String, String)] = [
            ("apps", EndpointRouter.apps),
            ("assets", EndpointRouter.assets),
            ("learn", EndpointRouter.learn),
            ("lecture", EndpointRouter.string("lecture-prod")),
            ("pay", EndpointRouter.pay),
            ("support", EndpointRouter.support),
            ("main", EndpointRouter.app),
        ]
        return endpoints.compactMap { (key, rawUrl) in
            guard !rawUrl.isEmpty, let host = URL(string: rawUrl)?.host else { return nil }
            return (host, rawUrl)
        }
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func performFetch(url: URL) async -> (Int, String, Error?) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue("GujoFleetAuditor/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            return (status, body, nil)
        } catch {
            return (0, "", error)
        }
    }

    private func evaluateAvailability(httpStatus: Int, fetchError: Error?) -> (CheckItem, [String]) {
        let isHealthy = (200..<400).contains(httpStatus)
        guard isHealthy else {
            let detail = fetchError.map { "Fetch failed: \($0.localizedDescription)" } ?? "Unhealthy HTTP \(httpStatus)"
            return (CheckItem(name: "Availability", maxScore: 30, score: 0, passed: false, details: detail), [detail])
        }
        return (CheckItem(name: "Availability", maxScore: 30, score: 30, passed: true, details: "HTTP \(httpStatus) response received"), [])
    }

    private func evaluateStability(httpStatus: Int, bodyString: String) -> (CheckItem, [String]) {
        var score = 25
        var issues: [String] = []
        let dumpSignatures = [
            "Ignition", "Whoops!", "Stack trace", "Fatal error", "SQLSTATE[",
            "Unhandled Exception", "Call to undefined function"
        ]
        for sig in dumpSignatures where bodyString.localizedCaseInsensitiveContains(sig) {
            score = 0
            issues.append("Crash signature detected: \(sig)")
            break
        }
        if httpStatus == 200 && bodyString.count < 100 {
            score = max(0, score - 15)
            issues.append("Body length suspicious (< 100 chars)")
        }
        let detail = issues.isEmpty ? "No error dumps or stacktraces" : issues.joined(separator: ", ")
        return (CheckItem(name: "Stability & Zero Error Dumps", maxScore: 25, score: score, passed: score == 25, details: detail), issues)
    }

    private func evaluateBranding(bodyString: String) -> (CheckItem, [String]) {
        var score = 25
        var issues: [String] = []
        let forbiddenEmojis = ["⚡️", "⚡", "⭐️", "⭐", "🚀"]
        for emoji in forbiddenEmojis where bodyString.contains(emoji) {
            score = max(0, score - 10)
            issues.append("Forbidden emoji present: \(emoji)")
        }

        let forbiddenPhrases = [
            "Envato Elements",
            "가장 인기 있는 플랜",
            "최고 가성비",
            "최저 비용"
        ]
        for phrase in forbiddenPhrases where bodyString.localizedCaseInsensitiveContains(phrase) {
            score = max(0, score - 15)
            issues.append("Forbidden copy present: '\(phrase)'")
        }

        let detail = issues.isEmpty ? "Clean copy, no forbidden emojis or speculative phrases" : issues.joined(separator: ", ")
        return (CheckItem(name: "Branding & Copy Discipline", maxScore: 25, score: score, passed: score == 25, details: detail), issues)
    }

    private func evaluateTrust(bodyString: String) -> (CheckItem, [String]) {
        var score = 20
        var issues: [String] = []

        let emptyIndicators = ["0개의 에셋", "0 items", "준비된 강의가 없습니다"]
        if emptyIndicators.contains(where: { bodyString.contains($0) }) {
            score = max(0, score - 10)
            issues.append("Empty shell content (0 items advertised)")
        }

        let hasAnchor = bodyString.localizedCaseInsensitiveContains("gujo") || bodyString.contains("©")
        if !hasAnchor {
            score = max(0, score - 5)
            issues.append("Missing Gujo copyright or branding anchor")
        }

        let detail = issues.isEmpty ? "Compliant business identity and non-empty content" : issues.joined(separator: ", ")
        return (CheckItem(name: "Legal, Trust & Completeness", maxScore: 20, score: score, passed: score >= 18, details: detail), issues)
    }

    public func auditSite(name: String, urlString: String) async -> SiteAuditResult {
        guard let url = URL(string: urlString) else {
            return SiteAuditResult(
                domain: name,
                url: urlString,
                httpStatus: 0,
                score: 0,
                passed: false,
                checks: [],
                issues: ["Invalid URL"]
            )
        }

        let (httpStatus, bodyString, fetchError) = await performFetch(url: url)

        let (availCheck, availIssues) = evaluateAvailability(httpStatus: httpStatus, fetchError: fetchError)
        let (stabCheck, stabIssues) = evaluateStability(httpStatus: httpStatus, bodyString: bodyString)
        let (brandCheck, brandIssues) = evaluateBranding(bodyString: bodyString)
        let (trustCheck, trustIssues) = evaluateTrust(bodyString: bodyString)

        let checks = [availCheck, stabCheck, brandCheck, trustCheck]
        let issues = availIssues + stabIssues + brandIssues + trustIssues
        let totalScore = checks.reduce(0) { $0 + $1.score }

        return SiteAuditResult(
            domain: name,
            url: urlString,
            httpStatus: httpStatus,
            score: totalScore,
            passed: totalScore >= 95,
            checks: checks,
            issues: issues
        )
    }

    public func auditFleet() async -> FleetReport {
        let targets = Self.targetDomains
        var resultsMap: [String: SiteAuditResult] = [:]

        await withTaskGroup(of: (String, SiteAuditResult).self) { group in
            for item in targets {
                group.addTask {
                    let res = await self.auditSite(name: item.name, urlString: item.url)
                    return (item.name, res)
                }
            }
            for await (name, res) in group {
                resultsMap[name] = res
            }
        }

        let orderedResults = targets.compactMap { resultsMap[$0.name] }
        let avg = Double(orderedResults.reduce(0) { $0 + $1.score }) / Double(max(1, orderedResults.count))
        let allPassed = orderedResults.allSatisfy(\.passed)

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        return FleetReport(
            timestamp: timestamp,
            averageScore: (avg * 10).rounded() / 10,
            allPassed: allPassed,
            sites: orderedResults
        )
    }
}
