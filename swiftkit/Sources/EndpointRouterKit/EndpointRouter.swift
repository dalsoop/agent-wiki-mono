import Foundation
import LocalizationKit
import StateRootKit

/// 키 → URL 라우터. 값은 빌드 앱(app-build-manager) 원장이 소유하고,
/// 앱은 키만 물어본다. 호스트 리터럴을 앱 소스에 두지 않는다.
///
/// 해석 우선순위(키별):
/// 1. env `GUJO_ENDPOINT_<KEY>`
/// 2. env `GUJO_ENDPOINTS_FILE`
/// 3. 빌드 앱 원장 `.app-build-manager/endpoints.json`
/// 4. 번들 폴백 표
public enum EndpointRouter {
    public static let schemaVersion = 1
    public static let ledgerRelativePath = ".app-build-manager/endpoints.json"

    public static let defaults: [String: String] = loadBundledDefaults()

    private static let resolvedTable: [String: String] = resolve(
        environment: ProcessInfo.processInfo.environment,
        homeDirectory: NSHomeDirectory()
    )

    public static var all: [String: String] { resolvedTable }

    public static var app: String { string("app") }
    public static var gujoCore: String { string("gujo-core") }
    public static var apps: String { string("apps") }
    public static var appsProd: String { string("apps-prod") }
    public static var assets: String { string("assets") }
    public static var assetsProd: String { string("assets-prod") }
    @available(*, deprecated, message: "EndpointRouter.assets 를 쓴다")
    public static var asset: String { assets }
    public static var support: String { string("support") }
    public static var supportProd: String { string("support-prod") }
    public static var pay: String { string("pay") }
    public static var payProd: String { string("pay-prod") }
    public static var learn: String { string("learn") }
    public static var learnProd: String { string("learn-prod") }
    public static var gpuPanel: String { string("gpu-panel") }

    public static func string(_ key: String) -> String {
        let lower = key.lowercased()
        if let val = resolvedTable[lower] { return val }
        let alt = lower.contains("-")
            ? lower.replacingOccurrences(of: "-", with: "_")
            : lower.replacingOccurrences(of: "_", with: "-")
        return resolvedTable[alt] ?? ""
    }

    public static func url(_ key: String) -> URL? {
        URL(string: string(key))
    }

    public static func catalogPageURL(id: Int, appsBase: String = EndpointRouter.apps) -> URL? {
        joining(appsBase, path: "catalog/\(id)")
    }

    public static func downloadsURL(appsBase: String = EndpointRouter.apps) -> URL? {
        joining(appsBase, path: "downloads")
    }

    public static func supportPageURL(supportBase: String = EndpointRouter.support) -> URL? {
        joining(supportBase, path: "")
    }

    public static func joining(_ base: String, path: String) -> URL? {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            return URL(string: trimmedBase)
        }
        let root = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        return URL(string: "\(root)/\(trimmedPath)")
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> [String: String] {
        var table = defaults
        let ledgerURL = ledgerFileURL(environment: environment, homeDirectory: homeDirectory)
        if let fromFile = loadTable(from: ledgerURL) {
            table.merge(fromFile) { _, fileValue in fileValue }
        }
        return applyEnvOverrides(to: table, environment: environment)
    }

    public static func ledgerFileURL(
        environment: [String: String],
        homeDirectory: String
    ) -> URL {
        if let override = environment["GUJO_ENDPOINTS_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).standardizingPath)
        }
        return StateRootKit.url(
            ledgerRelativePath,
            environment: environment,
            homeDirectory: homeDirectory
        )
    }

    private static func loadBundledDefaults() -> [String: String] {
        let bundle = ResourceBundle.named("swiftkit_EndpointRouterKit")
        guard let url = bundle.url(forResource: "endpoints-defaults", withExtension: "json") else {
            return [:]
        }
        return loadTable(from: url) ?? [:]
    }

    public static func loadTable(from url: URL) -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: url.path),
              !data.isEmpty else { return nil }
        struct LedgerFile: Decodable {
            var schemaVersion: Int
            var endpoints: [String: String]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let ledger = try decoder.decode(LedgerFile.self, from: data)
            guard ledger.schemaVersion == schemaVersion else { return nil }
            return Dictionary(uniqueKeysWithValues:
                ledger.endpoints.map { ($0.key.lowercased(), $0.value) })
        } catch {
            return nil
        }
    }

    public static func writeLedger(endpoints: [String: String], to url: URL) throws {
        struct LedgerFile: Encodable {
            var schemaVersion: Int
            var note: String
            var endpoints: [String: String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = LedgerFile(
            schemaVersion: schemaVersion,
            note: "Owned by app-build-manager. Apps read via EndpointRouterKit.",
            endpoints: Dictionary(uniqueKeysWithValues: endpoints.map { ($0.key.lowercased(), $0.value) })
        )
        let data = try encoder.encode(payload)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func applyEnvOverrides(
        to table: [String: String],
        environment: [String: String]
    ) -> [String: String] {
        var result = table
        for (name, value) in environment where name.hasPrefix("GUJO_ENDPOINT_") {
            let key = String(name.dropFirst("GUJO_ENDPOINT_".count)).lowercased()
            let isFileKey = key == "s_file" || key.hasSuffix("_file")
            guard !key.isEmpty, !isFileKey, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}
