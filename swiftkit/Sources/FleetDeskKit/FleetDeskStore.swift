#if canImport(Darwin)
import StateRootKit
import Darwin
#endif
import Foundation

extension Notification.Name {
    /// 정본 `fleet-desk.json` 이 바뀌었다. 각 프로세스가 자기 타일만 다시 맞춘다.
    public static let fleetDeskDidChange = Notification.Name("net.ranode.fleet-desk.didChange")
}

/// `~/.swift-app-state/fleet-desk.json` 의도. 실행 중 프로세스 정책은 바꾸지 않는다.
public enum FleetDeskStore: Sendable {
    public struct Flag: Codable, Equatable, Sendable {
        public var hideFleetDockIcons: Bool
        /// nil 이면 기본 허용 목록. 빈 배열이면 허브만.
        public var dockBundleIds: [String]?

        public init(hideFleetDockIcons: Bool, dockBundleIds: [String]? = nil) {
            self.hideFleetDockIcons = hideFleetDockIcons
            self.dockBundleIds = dockBundleIds
        }

        public var resolvedDockBundleIds: [String] {
            dockBundleIds ?? FleetDeskPolicy.defaultDockBundleIds
        }
    }

    /// 샌드박스 컨테이너가 아닌 실제 홈. `NSHomeDirectory` 는 컨테이너만 본다.
    public static func posixHome() -> URL {
        #if canImport(Darwin)
        if let pw = getpwuid(getuid()) {
            let dir = pw.pointee.pw_dir
            if let dir {
                return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
            }
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func flagURL(home: URL = URL(fileURLWithPath: StateRootKit.path(".swift-app-state"))) -> URL {
        home.appendingPathComponent("fleet-desk.json")
    }

    public static func flag(at url: URL? = nil) -> Flag {
        let candidates: [URL]
        if let url {
            candidates = [url]
        } else {
            let posix = flagURL()
            let container = flagURL(home: FileManager.default.homeDirectoryForCurrentUser)
            candidates = posix == container ? [posix] : [posix, container]
        }
        for file in candidates {
            do {
                let data = try Data(contentsOf: file)
                return try JSONDecoder().decode(Flag.self, from: data)
            } catch {
                // 후보 파일 부재는 미설정의 정상 상태고, 그 외 깨짐은 이유를 남긴다.
                if (error as NSError).code != NSFileReadUnknownError {
                    FileHandle.standardError.write(Data("fleet-desk: flag load failed: \(error.localizedDescription)\n".utf8))
                }
            }
        }
        return Flag(hideFleetDockIcons: false)
    }

    public static func isEnabled(at url: URL? = nil) -> Bool {
        flag(at: url).hideFleetDockIcons
    }

    public static func save(_ current: Flag, at url: URL? = nil) throws {
        let file = url ?? flagURL()
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(current)
        try data.write(to: file, options: .atomic)
        let canonical = flagURL().standardizedFileURL.path
        if file.standardizedFileURL.path == canonical {
            publishChange()
        }
    }

    public static func setEnabled(_ on: Bool, at url: URL? = nil) throws {
        var current = flag(at: url)
        current.hideFleetDockIcons = on
        if current.dockBundleIds == nil {
            current.dockBundleIds = FleetDeskPolicy.defaultDockBundleIds
        }
        try save(current, at: url)
    }

    /// 허브만 Dock에 남긴다. 허용 목록을 비운다.
    public static func hideAllFleet(at url: URL? = nil) throws {
        var current = flag(at: url)
        current.hideFleetDockIcons = true
        current.dockBundleIds = []
        try save(current, at: url)
    }

    public static func setDockAllowed(_ bundleId: String, allowed: Bool, at url: URL? = nil) throws {
        let id = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, FleetDeskIdentity.isFleet(id), !FleetDeskIdentity.isHub(id) else { return }
        var current = flag(at: url)
        var ids = Set(current.resolvedDockBundleIds.map { $0.lowercased() })
        if allowed {
            ids.insert(id.lowercased())
        } else {
            ids.remove(id.lowercased())
        }
        current.dockBundleIds = ids.sorted()
        try save(current, at: url)
    }

    public static func publishChange() {
        DistributedNotificationCenter.default().post(name: .fleetDeskDidChange, object: nil)
    }
}
