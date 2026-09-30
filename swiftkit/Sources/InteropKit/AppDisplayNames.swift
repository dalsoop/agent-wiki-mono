import Foundation

/// 설치된 앱 번들이 사람에게 보이는 이름 — 영어 표시명과 한글 표시명.
///
/// 레지스트리 항목(`Capabilities.displayName`/`displayNameKo`)의 원천이다. 앱은 이 값을
/// capabilities 에 적지 않는다: 이름의 정본은 번들의 `Info.plist` 와 `ko.lproj` 번역이고,
/// 레지스트리는 upsert 할 때 설치본에서 읽어 옮긴다.
///
/// 없으면 어떤 일이 벌어지는가(2026-09-29): 레지스트리에는 kebab CLI 이름과 영어
/// purpose 만 있어서 "라라벨 클라우드" 나 "가드레일 관리자" 같은 한글 UI 이름으로는
/// `agent-search-engine` 이 앱을 못 찾았다.
public struct AppDisplayNames: Equatable, Sendable {
    public var displayName: String?
    public var displayNameKo: String?

    public init(displayName: String? = nil, displayNameKo: String? = nil) {
        self.displayName = displayName
        self.displayNameKo = displayNameKo
    }

    /// 번들을 bundleId 로 찾을 때 훑는 곳 — 로컬·사용자 `Applications`.
    public static var defaultApplicationDirectories: [String] {
        FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask]).map(\.path)
    }

    /// 한글 표시명 후보로 보는 L10n 키. `ko.lproj/InfoPlist.strings` 가 없을 때만 쓴다.
    static let localizableNameKeys = ["app.displayName", "app.name", "app.title"]

    /// `cli`(Helpers 심링크) 또는 `bundleId` 로 설치 번들을 찾아 이름을 읽는다.
    public static func resolve(
        bundleId: String,
        cli: String,
        applicationDirectories: [String] = AppDisplayNames.defaultApplicationDirectories
    ) -> AppDisplayNames {
        guard let bundle = locateBundle(
            bundleId: bundleId, cli: cli, applicationDirectories: applicationDirectories
        ) else { return AppDisplayNames() }
        return read(bundlePath: bundle)
    }

    /// `.app` 번들 하나에서 이름을 읽는다.
    ///
    /// - 영어: `CFBundleDisplayName` → `CFBundleName`.
    /// - 한글: `ko.lproj/InfoPlist.strings` 의 `CFBundleDisplayName` → `CFBundleName`,
    ///   없으면 `ko.lproj/Localizable.strings`(번들 리소스와 그 안의 `.bundle` 포함)의
    ///   `app.displayName`·`app.name`·`app.title`. 한글이 없는 값은 한글 이름으로 치지 않는다
    ///   (`"app.name" = "agent-work-todo"` 같은 번역 안 된 값이 흔하다).
    public static func read(bundlePath: String) -> AppDisplayNames {
        let contents = (bundlePath as NSString).appendingPathComponent("Contents")
        let resources = (contents as NSString).appendingPathComponent("Resources")
        let info = dictionary(atPath: (contents as NSString).appendingPathComponent("Info.plist"))
        let english = firstNonEmpty(info, keys: ["CFBundleDisplayName", "CFBundleName"])

        var korean: String?
        let infoKo = dictionary(atPath: (resources as NSString).appendingPathComponent("ko.lproj/InfoPlist.strings"))
        if let name = firstNonEmpty(infoKo, keys: ["CFBundleDisplayName", "CFBundleName"]), containsHangul(name) {
            korean = name
        }
        if korean == nil {
            for table in localizableTables(resources: resources) {
                let strings = dictionary(atPath: table)
                if let name = firstNonEmpty(strings, keys: localizableNameKeys), containsHangul(name) {
                    korean = name
                    break
                }
            }
        }
        return AppDisplayNames(displayName: english, displayNameKo: korean)
    }

    static func containsHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    // MARK: - private

    private static func locateBundle(
        bundleId: String,
        cli: String,
        applicationDirectories: [String]
    ) -> String? {
        let fm = FileManager.default
        if !cli.isEmpty {
            let resolved = URL(fileURLWithPath: cli).resolvingSymlinksInPath().path
            if let range = resolved.range(of: ".app/Contents/") {
                let bundle = String(resolved[..<range.lowerBound]) + ".app"
                if fm.fileExists(atPath: bundle) { return bundle }
            }
        }
        guard !bundleId.isEmpty else { return nil }
        for dir in applicationDirectories {
            // 없는 디렉터리는 enumerator 가 nil — 번들이 없는 것과 같다.
            guard let entries = fm.enumerator(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in entries where url.pathExtension == "app" {
                let bundle = url.path
                let info = dictionary(atPath: bundle + "/Contents/Info.plist")
                if info["CFBundleIdentifier"] as? String == bundleId { return bundle }
            }
        }
        return nil
    }

    private static func localizableTables(resources: String) -> [String] {
        var tables = [(resources as NSString).appendingPathComponent("ko.lproj/Localizable.strings")]
        let children: [String]
        do {
            children = try FileManager.default.contentsOfDirectory(atPath: resources)
        } catch {
            return tables
        }
        for child in children.sorted() where child.hasSuffix(".bundle") {
            tables.append((resources as NSString).appendingPathComponent("\(child)/ko.lproj/Localizable.strings"))
            tables.append((resources as NSString).appendingPathComponent("\(child)/Contents/Resources/ko.lproj/Localizable.strings"))
        }
        return tables
    }

    /// plist 와 `.strings`(옛 plist 문법) 모두 `PropertyListSerialization` 이 읽는다.
    private static func dictionary(atPath path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        do {
            let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return obj as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }

    private static func firstNonEmpty(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            let value = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return nil
    }
}

extension Capabilities {
    /// 설치 번들에서 표시명을 읽어 채운 사본. 번들을 못 찾거나 값이 없으면 기존 값을 둔다.
    public func resolvingDisplayNames(
        applicationDirectories: [String] = AppDisplayNames.defaultApplicationDirectories
    ) -> Capabilities {
        let names = AppDisplayNames.resolve(
            bundleId: bundleId, cli: cli, applicationDirectories: applicationDirectories
        )
        var copy = self
        copy.displayName = names.displayName ?? displayName
        copy.displayNameKo = names.displayNameKo ?? displayNameKo
        return copy
    }
}
