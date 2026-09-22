import Foundation

/// 최근 hub/함대 점검 시각 — NEXT 신선도용.
public enum ServiceOpsContext {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Gujo/service-ops", isDirectory: true)
    }

    public static var fileURL: URL {
        directory.appendingPathComponent("context.json")
    }

    public struct Snapshot: Codable, Sendable {
        public var lastHubReadyAt: Date?
        public var lastHubReady: Bool?
        public var lastFleetHealth: String?
        public var updatedAt: Date

        public init(
            lastHubReadyAt: Date? = nil,
            lastHubReady: Bool? = nil,
            lastFleetHealth: String? = nil,
            updatedAt: Date = Date()
        ) {
            self.lastHubReadyAt = lastHubReadyAt
            self.lastHubReady = lastHubReady
            self.lastFleetHealth = lastFleetHealth
            self.updatedAt = updatedAt
        }
    }

    public static func load() -> Snapshot {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if isMissingFile(error) { return Snapshot() }
            fputs("service-ops context read failed: \(error.localizedDescription)\n", stderr)
            return Snapshot()
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(Snapshot.self, from: data)
        } catch {
            fputs("service-ops context decode failed: \(error.localizedDescription)\n", stderr)
            return Snapshot()
        }
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError
    }

    public static func recordHub(ready: Bool) {
        var s = load()
        s.lastHubReady = ready
        if ready { s.lastHubReadyAt = Date() }
        s.updatedAt = Date()
        save(s)
    }

    public static func recordFleet(health: String) {
        var s = load()
        s.lastFleetHealth = health
        s.updatedAt = Date()
        save(s)
    }

    /// hub 가 이 분 안에 READY 였으면 true
    public static func hubReadyWithin(minutes: Int) -> Bool {
        let s = load()
        guard s.lastHubReady == true, let t = s.lastHubReadyAt else { return false }
        return Date().timeIntervalSince(t) < Double(minutes * 60)
    }

    private static func save(_ s: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(s)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("service-ops context save failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
