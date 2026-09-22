import Foundation

/// product_id → CFBundleIdentifier.
/// 정본은 각 앱 `gujo-product.json` + `Packaging/Info.plist`.
/// git 에 숫자표를 두지 않는다. 구매자 설치본에는 ship 이 이 JSON 을 번들에 심는다.
public enum SparkleProductIndex: Sendable {
    public static let resourceName = "product-bundle-index"
    public static let resourceExtension = "json"
    public static let cloudAppsBundleID = "net.ranode.gujo-cloud-apps"

    public struct Entry: Codable, Sendable, Equatable {
        public let productId: Int
        public let bundleID: String
        public init(productId: Int, bundleID: String) {
            self.productId = productId
            self.bundleID = bundleID
        }
    }

    public static func load(appsRoot: URL, fileManager: FileManager = .default) -> [Int: String] {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: appsRoot.path)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch {
            return [:]
        }
        var map: [Int: String] = [:]
        for name in names {
            if name.hasSuffix("-ios") { continue }
            let dir = appsRoot.appendingPathComponent(name)
            guard let productId = readProductId(directory: dir, fileManager: fileManager),
                  let bundleID = bundleID(in: dir, fileManager: fileManager)
            else { continue }
            if map[productId] == nil || name.hasSuffix("-swift") {
                map[productId] = bundleID
            }
        }
        return map
    }

    public static func jsonData(from map: [Int: String]) throws -> Data {
        let rows = map.keys.sorted().compactMap { id -> Entry? in
            guard let bundleID = map[id] else { return nil }
            return Entry(productId: id, bundleID: bundleID)
        }
        return try JSONEncoder().encode(rows)
    }

    public static func map(fromJSON data: Data) throws -> [Int: String] {
        let rows = try JSONDecoder().decode([Entry].self, from: data)
        var map: [Int: String] = [:]
        for row in rows where !row.bundleID.isEmpty {
            map[row.productId] = row.bundleID
        }
        return map
    }

    public static func loadBundled(in bundle: Bundle) -> [Int: String] {
        guard let url = bundle.url(
            forResource: resourceName, withExtension: resourceExtension
        ) else { return [:] }
        return loadJSON(at: url)
    }

    /// Helpers CLI 는 Bundle.main 이 .app 이 아니다. 실행 파일에서 올려 .app 을 찾는다.
    public static func enclosingAppBundle(from executablePath: String) -> URL? {
        var url = URL(fileURLWithPath: executablePath)
        for _ in 0..<8 {
            if url.pathExtension == "app" { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return nil
    }

    public static func loadFromAppBundle(_ app: URL) -> [Int: String] {
        loadJSON(at: resourceURL(inAppBundle: app))
    }

    public static func resourceURL(inAppBundle app: URL) -> URL {
        app.appendingPathComponent("Contents/Resources/\(resourceName).\(resourceExtension)")
    }

    private static func loadJSON(at url: URL) -> [Int: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            return try map(fromJSON: Data(contentsOf: url))
        } catch {
            return [:]
        }
    }

    /// 스테이징 `.app` 의 Resources 에 스냅샷을 쓴다. 소스 트리 스캔이 비면 쓰지 않는다.
    @discardableResult
    public static func embed(
        intoAppBundle app: URL,
        appsRoot: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let map = load(appsRoot: appsRoot, fileManager: fileManager)
        guard !map.isEmpty else { return 0 }
        let dest = resourceURL(inAppBundle: app)
        try fileManager.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonData(from: map).write(to: dest, options: .atomic)
        return map.count
    }

    private static func readProductId(directory: URL, fileManager: FileManager) -> Int? {
        let url = directory.appendingPathComponent("gujo-product.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = fileManager.contents(atPath: url.path)
        else { return nil }
        struct File: Decodable {
            struct Binding: Decodable { let product_id: Int }
            let binding: Binding
        }
        do {
            return try JSONDecoder().decode(File.self, from: data).binding.product_id
        } catch {
            return nil
        }
    }

    private static func bundleID(in appDir: URL, fileManager: FileManager) -> String? {
        let plist = appDir.appendingPathComponent("Packaging/Info.plist")
        guard fileManager.fileExists(atPath: plist.path),
              let data = fileManager.contents(atPath: plist.path)
        else { return nil }
        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            return nil
        }
        guard let dict = obj as? [String: Any],
              let bid = dict["CFBundleIdentifier"] as? String,
              !bid.isEmpty
        else { return nil }
        return bid
    }
}
