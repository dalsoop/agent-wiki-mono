import Foundation
import CoreServices
import StateRootKit

public enum PersistentFSEventsWatcher: Sendable {
    private final class FSEventsAccumulator: @unchecked Sendable {
        var changedPaths = [String]()
        var latestEventId: UInt64
        let lock = NSLock()

        init(lastEventId: UInt64) {
            self.latestEventId = lastEventId
        }

        func add(paths: [String], eventIds: [UInt64]) {
            lock.lock()
            defer { lock.unlock() }
            changedPaths.append(contentsOf: paths)
            for id in eventIds {
                if id > latestEventId {
                    latestEventId = id
                }
            }
        }
    }

    public static func queryChangesSince(
        lastEventId: UInt64,
        paths: [String]
    ) async -> (changedPaths: [String], latestEventId: UInt64) {
        guard !paths.isEmpty else {
            return ([], lastEventId)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let currentSystemEventId = FSEventsGetCurrentEventId()
                let initialLatestId = max(lastEventId, currentSystemEventId)
                let accumulator = FSEventsAccumulator(lastEventId: initialLatestId)

                var context = FSEventStreamContext(
                    version: 0,
                    info: Unmanaged.passRetained(accumulator).toOpaque(),
                    retain: nil,
                    release: { info in
                        guard let info else { return }
                        Unmanaged<FSEventsAccumulator>.fromOpaque(info).release()
                    },
                    copyDescription: nil
                )

                let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, eventIds in
                    guard let info else { return }
                    let acc = Unmanaged<FSEventsAccumulator>.fromOpaque(info).takeUnretainedValue()
                    let pathsPtr = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                    var p = [String]()
                    p.reserveCapacity(numEvents)
                    var ids = [UInt64]()
                    ids.reserveCapacity(numEvents)
                    for i in 0..<numEvents {
                        p.append(String(cString: pathsPtr[i]))
                        ids.append(eventIds[i])
                    }
                    acc.add(paths: p, eventIds: ids)
                }

                let sinceWhen: FSEventStreamEventId
                if lastEventId == 0 {
                    sinceWhen = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
                } else {
                    sinceWhen = FSEventStreamEventId(lastEventId)
                }

                let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
                guard let stream = FSEventStreamCreate(
                    kCFAllocatorDefault,
                    callback,
                    &context,
                    paths as CFArray,
                    sinceWhen,
                    0.0,
                    flags
                ) else {
                    Unmanaged<FSEventsAccumulator>.fromOpaque(context.info!).release()
                    continuation.resume(returning: ([], lastEventId))
                    return
                }

                let queue = DispatchQueue(label: "fastdiskio.fsevents.\(UUID().uuidString)")
                FSEventStreamSetDispatchQueue(stream, queue)
                FSEventStreamStart(stream)

                FSEventStreamFlushSync(stream)
                queue.sync {}

                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)

                accumulator.lock.lock()
                var seen = Set<String>()
                var uniquePaths = [String]()
                for p in accumulator.changedPaths {
                    if seen.insert(p).inserted {
                        uniquePaths.append(p)
                    }
                }
                let latestId = accumulator.latestEventId
                accumulator.lock.unlock()

                continuation.resume(returning: (uniquePaths, latestId))
            }
        }
    }
}

public enum EventBookmarkStore: Sendable {
    private struct Bookmark: Codable {
        let name: String
        let eventId: UInt64
        let savedAt: Date
    }

    public static func bookmarkDirectory() -> URL {
        StateRootKit.url(".swift-app-state/fsevents-bookmarks")
    }

    public static func bookmarkURL(for name: String) -> URL {
        bookmarkDirectory().appendingPathComponent("\(name).json")
    }

    public static func load(name: String) -> UInt64? {
        let url = bookmarkURL(for: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let bm = try JSONDecoder().decode(Bookmark.self, from: data)
            return bm.eventId
        } catch {
            // fallback to dictionary parsing
        }
        do {
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = dict["eventId"] as? UInt64 ?? (dict["eventId"] as? NSNumber)?.uint64Value {
                return id
            }
        } catch {
            return nil
        }
        return nil
    }

    public static func save(eventId: UInt64, for name: String) throws {
        let dir = bookmarkDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bm = Bookmark(name: name, eventId: eventId, savedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bm)
        let url = bookmarkURL(for: name)
        try data.write(to: url, options: .atomic)
    }
}
