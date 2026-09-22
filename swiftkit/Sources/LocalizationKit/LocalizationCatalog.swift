import Foundation

/// `.lproj/Localizable.strings` 를 **파일로 직접** 읽는 조회 표면.
///
/// 배경(2026-09-04 CI 실측): Linux(swift-corelibs-foundation) 에서 SwiftPM 이 만드는
/// 평면 리소스 번들(`<Pkg>_<Target>.bundle`, Info.plist 없음)은 CFBundle 이 번들로
/// 인식하지 못한다 — `Bundle(url:)` · `path(forResource:ofType:"lproj")` ·
/// `localizedString(forKey:)` 가 줄줄이 빈손이라 native-lint 게이트 출력이 통째로
/// 키(`cli.contracts.ok_row`)로 샜다. 게이트가 사람에게 아무 말도 못 하면 게이트가 아니다.
///
/// 그래서 번들 API 를 거치지 않는 축을 하나 둔다. `FileManager` 와
/// `PropertyListSerialization` 만 쓰므로 플랫폼에 따라 결과가 달라지지 않는다.
/// macOS 에선 번들 경로가 먼저 성공하므로 이 축은 폴백으로만 걸린다.
public struct LocalizationCatalog: Sendable {
    /// `.lproj` 들이 놓인 디렉터리 — 번들 최상위(평면) 또는 `Contents/Resources`(macOS).
    public let root: URL

    public init(root: URL) { self.root = root }

    /// 이 카탈로그가 **실제로 담고 있는** 번역 목록(`Base` 제외, 정렬).
    public func availableLocalizations(fileManager fm: FileManager = .default) -> [String] {
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != "Base" }
            .sorted()
    }

    /// 시스템 우선 언어를 이 카탈로그가 담은 번역 중에서 고른다.
    ///
    /// `Bundle.preferredLocalizations` 를 쓰지 않는 건 이 타입의 존재 이유와 같다 —
    /// 번들로 인식되지 않는 디렉터리에선 그 API 도 빈손이다. 지역 변종(`ko-KR` → `ko`)은
    /// 언어 코드 접두로 맞춘다.
    public func systemLocalization(
        preferences: [String] = Locale.preferredLanguages,
        fileManager fm: FileManager = .default
    ) -> String? {
        let available = availableLocalizations(fileManager: fm)
        guard !available.isEmpty else { return nil }
        for preference in preferences {
            let language = preference.split(separator: "-").first.map(String.init) ?? preference
            if let hit = available.first(where: {
                $0 == preference || $0 == language || $0.hasPrefix(language + "-")
            }) { return hit }
        }
        return available.contains("en") ? "en" : available.first
    }

    /// `preferred` 순서로 찾고, 없으면 `en`, 그다음 담고 있는 첫 번역.
    ///
    /// 키가 어느 표에도 없으면 `nil` — 호출자가 키를 그대로 내보낼지 정한다
    /// (누락은 키 노출로 드러나야 테스트가 잡는다).
    public func string(
        _ key: String,
        preferred: [String],
        fileManager fm: FileManager = .default
    ) -> String? {
        var codes = preferred
        codes.append("en")
        codes.append(contentsOf: availableLocalizations(fileManager: fm))
        var seen = Set<String>()
        for code in codes where seen.insert(code).inserted {
            if let value = table(code, fileManager: fm)?[key] { return value }
        }
        return nil
    }

    /// 한 `.lproj` 의 표. 파일이 없거나 못 읽으면 nil.
    func table(_ code: String, fileManager fm: FileManager = .default) -> [String: String]? {
        let url = root
            .appendingPathComponent("\(code).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        guard fm.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return Self.parse(text)
    }

    /// `.strings` 본문 → 표.
    ///
    /// openstep 프로퍼티 리스트로 먼저 읽는다(정본 파서). 그 길이 막히면 줄 파서로
    /// 떨어진다 — 이 타입이 애초에 플랫폼 파서 불신 때문에 생겼으니 여기서 다시
    /// 한 파서에 목을 걸지 않는다.
    static func parse(_ text: String) -> [String: String] {
        guard let dictionary = plistTable(text) else { return parsePairs(text) }
        return dictionary
    }

    /// openstep 프로퍼티 리스트로 읽어 본다. **이 플랫폼이 이 형식을 모르면** nil —
    /// 그 판정이 곧 줄 파서로 떨어지는 조건이라 에러 본문에 더 물어볼 게 없다.
    static func plistTable(_ text: String) -> [String: String]? {
        guard let data = text.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: String],
              !dictionary.isEmpty
        else { return nil }
        return dictionary
    }

    /// `"키" = "값";` 쌍만 뽑는 최소 파서. 주석 안의 쌍까지 구분하지는 않는다.
    static func parsePairs(_ text: String) -> [String: String] {
        let pattern = #""((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [:] }
        let ns = text as NSString
        var out: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let key = unescape(ns.substring(with: match.range(at: 1)))
            out[key] = unescape(ns.substring(with: match.range(at: 2)))
        }
        return out
    }

    static func unescape(_ raw: String) -> String {
        var out = ""
        var iterator = raw.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escaped = iterator.next() else {
                out.append(character)
                continue
            }
            switch escaped {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            default: out.append(escaped)
            }
        }
        return out
    }
}
