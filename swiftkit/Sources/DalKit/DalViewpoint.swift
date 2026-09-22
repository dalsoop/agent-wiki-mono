import Foundation

/// 시점 축. dal-* 기본은 철저 1인칭. 3인칭·unknown 쓰기는 거부.
public enum DalViewpoint: String, Sendable, Equatable, CaseIterable {
    case first
    case third
    case unknown

    public static let allowedWrite = DalViewpoint.first

    public static func parse(_ raw: String?) -> DalViewpoint {
        let value = (raw ?? "first").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DalViewpoint(rawValue: value) ?? .unknown
    }

    public static func requireFirst(_ raw: String?) throws -> String {
        let v = parse(raw)
        guard v == .first else { throw DalKitError.viewpointRejected(v.rawValue) }
        return first.rawValue
    }

    public static func isFirst(_ raw: String?) -> Bool {
        parse(raw) == .first
    }
}

/// 문장 표면이 1인칭/3인칭처럼 보이는지 — doctor·ingest 경고용.
public enum DalPersonGrammar: Sendable {
    private static let firstMarkers = ["나는", "내가", "내 ", "우리를", "우리가", "저는", "제가"]
    private static let thirdMarkers = ["그는", "그가", "그녀는", "그녀가", "그들은", "그들은"]

    public static func looksFirstPerson(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return firstMarkers.contains { t.contains($0) }
    }

    public static func looksThirdPerson(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksFirstPerson(t) { return false }
        if thirdMarkers.contains(where: { t.contains($0) }) { return true }
        // 「X은/는 …이다」고유명사 서술 — 3인칭 관찰 문장 후보
        if t.contains("은 ") || t.contains("는 ") {
            if !t.hasPrefix("나") && !t.hasPrefix("저") { return true }
        }
        return false
    }
}
