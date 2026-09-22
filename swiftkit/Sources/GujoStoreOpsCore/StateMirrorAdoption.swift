import Foundation
import StateRootKit
#if canImport(StateMirrorKit)
import StateMirrorKit
#endif

/// Store Ops 관찰 채널 — `~/.swift-app-state/gujo-store-ops.json`
public enum StateMirrorAdoption {
    public static let appName = "gujo-store-ops"

    public struct State: Codable, Sendable {
        public var status: String
        public var generatedAt: Date
        public var hubReady: Bool?
        public var fleetHealth: String?
        public var fleetSummary: String?
        public var jobsRegistered: Int?
        public var jobsTotal: Int?
        public var seatsPresent: Int?
        public var seatsTotal: Int?
        public var tokenSet: Bool?
        public var nextStep: String?

        public init(
            status: String,
            generatedAt: Date = Date(),
            hubReady: Bool? = nil,
            fleetHealth: String? = nil,
            fleetSummary: String? = nil,
            jobsRegistered: Int? = nil,
            jobsTotal: Int? = nil,
            seatsPresent: Int? = nil,
            seatsTotal: Int? = nil,
            tokenSet: Bool? = nil,
            nextStep: String? = nil
        ) {
            self.status = status
            self.generatedAt = generatedAt
            self.hubReady = hubReady
            self.fleetHealth = fleetHealth
            self.fleetSummary = fleetSummary
            self.jobsRegistered = jobsRegistered
            self.jobsTotal = jobsTotal
            self.seatsPresent = seatsPresent
            self.seatsTotal = seatsTotal
            self.tokenSet = tokenSet
            self.nextStep = nextStep
        }
    }

    public static func publish(
        status: String = "ok",
        hubReady: Bool? = nil,
        fleet: GujoServiceOpsFleetSnapshot? = nil,
        tokenSet: Bool? = nil
    ) {
        let jobsReg = fleet.map { $0.jobs.filter(\.registered).count }
        let seatsOk = fleet.map { $0.seats.filter(\.present).count }
        let state = State(
            status: status,
            hubReady: hubReady,
            fleetHealth: fleet?.health,
            fleetSummary: fleet?.summary,
            jobsRegistered: jobsReg,
            jobsTotal: fleet?.jobs.count,
            seatsPresent: seatsOk,
            seatsTotal: fleet?.seats.count,
            tokenSet: tokenSet,
            nextStep: fleet?.nextSteps.first
        )
        #if canImport(StateMirrorKit)
        StateMirror.publish(app: appName, state)
        #else
        // iOS / 미링크 폴백 — Application Support 아님, 공용 경로에 JSON
        let dir = StateRootKit.url(".swift-app-state")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fputs("state-mirror: createDirectory failed: \(error.localizedDescription)\n", stderr)
            return
        }
        let url = dir.appendingPathComponent("\(appName).json")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("state-mirror: write failed: \(error.localizedDescription)\n", stderr)
        }
        #endif
    }
}
