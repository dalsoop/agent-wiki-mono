import CoreServices
import Foundation
import InteropKit
import os

private struct BridgeEngineState: Sendable {
    var streamAddress: UInt = 0
    var isRunning = false
}

public final class AwoRoomBridgeEngine: Sendable {
    public static let shared = AwoRoomBridgeEngine()

    private let store: InvertedStateStore
    private let queue = DispatchQueue(label: "ai.gujo.awo.bridge-pipeline", qos: .userInteractive)
    
    private let state = OSAllocatedUnfairLock(initialState: BridgeEngineState())

    private let placementDir: String
    private let blueprintDir: String
    private let awoDataDir: String
    private let stateMirrorDir: String

    public init(store: InvertedStateStore = .shared) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.placementDir = "\(home)/.agent-work-todo/store-v2/placements"
        self.blueprintDir = "\(home)/.agent-work-todo/store-v2/blueprints"
        self.awoDataDir = "\(home)/Library/Application Support/agent-worker-orchestrator"
        self.stateMirrorDir = "\(home)/.swift-app-state"
    }

    public func start() {
        let isAlreadyRunning = state.withLock { s -> Bool in
            if s.isRunning { return true }
            s.isRunning = true
            return false
        }
        guard !isAlreadyRunning else { return }

        triggerSync()
        setupFSEventStream()
    }

    public func stop() {
        let address = state.withLock { s -> UInt in
            guard s.isRunning else { return 0 }
            s.isRunning = false
            let old = s.streamAddress
            s.streamAddress = 0
            return old
        }

        if let stream = FSEventStreamRef(bitPattern: address) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func setupFSEventStream() {
        var pathsToWatch: [CFString] = []
        for d in [placementDir, awoDataDir, stateMirrorDir] {
            if FileManager.default.fileExists(atPath: d) {
                pathsToWatch.append(d as CFString)
            }
        }
        guard !pathsToWatch.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        let callback: FSEventStreamCallback = { streamRef, clientInfo, numEvents, eventPaths, eventFlags, eventIds in
            guard let info = clientInfo else { return }
            let engine = Unmanaged<AwoRoomBridgeEngine>.fromOpaque(info).takeUnretainedValue()
            engine.handleFSEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.02,
            flags
        ) else { return }

        let address = UInt(bitPattern: stream)
        state.withLock { $0.streamAddress = address }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func handleFSEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>) {
        triggerSync()
    }

    public func triggerSync() {
        queue.async {
            let rooms = self.loadActiveRooms()
            let blueprints = self.loadBlueprints()
            let jobs = self.loadLiveAwoJobs()

            self.store.commit(rooms: rooms, jobs: jobs, blueprints: blueprints)
        }
    }

    private func loadActiveRooms() -> [BridgeRoomSummary] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: placementDir) else { return [] }
        guard let files = try? fm.contentsOfDirectory(atPath: placementDir) else { return [] }

        var results: [BridgeRoomSummary] = []
        for file in files where file.hasSuffix(".json") {
            let url = URL(fileURLWithPath: "\(placementDir)/\(file)")
            do {
                let data = try Data(contentsOf: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                let planID = json["id"] as? String ?? ""
                let planState = json["state"] as? String ?? ""
                guard planState == "executing" else { continue }

                let title = json["title"] as? String ?? ""
                let tenantID = json["tenantID"] as? String ?? "tenant:personal"
                let planWorkdir = json["workdir"] as? String

                if let rooms = json["rooms"] as? [[String: Any]] {
                    for r in rooms {
                        let rState = r["state"] as? String ?? ""
                        guard rState == "occupied" || rState == "waiting" else { continue }
                        let rID = r["id"] as? String ?? UUID().uuidString
                        let bpSlug = r["blueprintSlug"] as? String ?? ""
                        let occupant = r["occupant"] as? String ?? ""
                        let handle = r["occupantHandle"] as? String ?? ""
                        let workdir = r["workdir"] as? String ?? planWorkdir

                        results.append(
                            BridgeRoomSummary(
                                id: rID,
                                planID: planID,
                                title: title,
                                blueprintSlug: bpSlug,
                                occupant: occupant,
                                occupantHandle: handle,
                                workdir: workdir,
                                canonicalWorkdir: AttributionEngine.canonicalPath(workdir),
                                state: rState,
                                tenantID: tenantID,
                                toolbelt: []
                            )
                        )
                    }
                }
            } catch {
                continue
            }
        }
        return results
    }

    private func loadBlueprints() -> [String: [String]] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: blueprintDir) else { return [:] }
        guard let files = try? fm.contentsOfDirectory(atPath: blueprintDir) else { return [:] }

        var map: [String: [String]] = [:]
        for file in files where file.hasSuffix(".json") {
            let url = URL(fileURLWithPath: "\(blueprintDir)/\(file)")
            do {
                let data = try Data(contentsOf: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                guard let spec = json["spec"] as? [String: Any],
                      let slug = spec["slug"] as? String else { continue }
                let toolbelt = spec["toolbelt"] as? [String] ?? []
                map[slug] = toolbelt
            } catch {
                continue
            }
        }
        return map
    }

    private func loadLiveAwoJobs() -> [BridgeJobSummary] {
        let mirrorURL = URL(fileURLWithPath: "\(stateMirrorDir)/agent-worker-orchestrator.json")
        do {
            let data = try Data(contentsOf: mirrorURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = obj["state"] as? [String: Any],
                  let rawJobs = state["jobs"] as? [[String: Any]] else {
                return []
            }

            return rawJobs.compactMap { raw -> BridgeJobSummary? in
                guard let id = raw["id"] as? String,
                      let title = raw["title"] as? String,
                      let stateStr = raw["state"] as? String else { return nil }

                let sinceSec = raw["since"] as? Double ?? Date().timeIntervalSince1970
                let since = Date(timeIntervalSince1970: sinceSec)
                let tenantID = raw["tenantID"] as? String
                let originObj = raw["origin"] as? [String: Any]
                var origin: OriginRef?
                if let app = originObj?["app"] as? String,
                   let rID = originObj?["roomID"] as? String,
                   let mID = originObj?["messageID"] as? String {
                    origin = OriginRef(app: app, roomID: rID, messageID: mID, replyTo: originObj?["replyTo"] as? String)
                }

                return BridgeJobSummary(
                    id: id,
                    title: title,
                    state: stateStr,
                    detailedPhase: BridgeJobPhase(rawValue: stateStr) ?? .runningWorker,
                    workdir: "",
                    canonicalWorkdir: "",
                    tenantID: tenantID,
                    origin: origin,
                    claimedBy: nil,
                    processID: nil,
                    logPath: "\(awoDataDir)/logs/\(id).log",
                    since: since,
                    progressRatio: nil
                )
            }
        } catch {
            return []
        }
    }
}
