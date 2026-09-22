import Foundation

/// 함대 마케팅 버전(`CFBundleShortVersionString`) 거절 정본.
///
/// Foundation 만. Linux native-lint 와 macOS ship 이 같은 함수를 쓴다.
/// 빌드 번호 epoch·plist IO·Sparkle 주입은 `ShipBundleStamp` 가 소유한다.
public enum MarketingVersion: Sendable {
    /// 사용자가 실패로 지정한 자리표기. `1.0.0` 은 첫 출시 값이라 허용.
    public static func placeholderReason(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "마케팅 버전이 비어 있다. app-build-manager set-version <앱dir> 1.0.0"
        }
        if trimmed == "1" || trimmed == "1.0" || trimmed == "1.00" {
            return "마케팅 버전 \(trimmed) 은 자리표기다 (1.00). app-build-manager set-version <앱dir> 1.0.0"
        }
        if isDevelopmentPlaceholder(trimmed) {
            return "마케팅 버전 \(trimmed) 은 개발 자리다. 승격하지 않는다. app-build-manager set-version <앱dir> 1.0.0"
        }
        return nil
    }

    public static func isDevelopmentPlaceholder(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "0" || trimmed.hasPrefix("0.")
    }

    /// release ship · set-version · lint 가 거절하는 이유. 자리표기 + `X.Y.Z` 숫자 세 칸.
    public static func refuseReason(_ raw: String?) -> String? {
        if let why = placeholderReason(raw) { return why }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard parse(trimmed) != nil else {
            return "마케팅 버전 \(trimmed) 은 X.Y.Z 숫자 세 칸이 아니다. app-build-manager set-version <앱dir> 1.0.0"
        }
        return nil
    }

    /// `1.2.3` 만. 선행 0(`01`)·네 칸·접미사 금지.
    public static func parse(_ raw: String) -> (Int, Int, Int)? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var nums: [Int] = []
        for part in parts {
            let s = String(part)
            guard let n = Int(s), String(n) == s else { return nil }
            nums.append(n)
        }
        return (nums[0], nums[1], nums[2])
    }

    public static func shortVersion(fromPlistXML text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let raw = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 설치본 마케팅보다 **작으면** 거절. 같은 마케팅 + 더 큰 빌드(epoch)는 허용.
    public static func refuseIfNotAscending(staged: String, installed: String?) -> String? {
        guard let installedRaw = installed?.trimmingCharacters(in: .whitespacesAndNewlines),
              !installedRaw.isEmpty,
              let stagedParts = parse(staged.trimmingCharacters(in: .whitespacesAndNewlines)),
              let installedParts = parse(installedRaw)
        else { return nil }
        if compare(stagedParts, installedParts) == .orderedAscending {
            return "설치본 마케팅 \(installedRaw) 보다 작다(스테이지 \(staged)). 마케팅 버전은 되돌릴 수 없다."
        }
        return nil
    }

    /// lint/`marketing-version-bump` 용. **ship 게이트가 아니다.**
    /// 로컬 설치는 같은 short + 더 큰 epoch 를 허용한다 (`refuseIfNotAscending`).
    public static func refuseIfSameWhileSourceStale(
        staged: String,
        installed: String?,
        sourceIsStale: Bool
    ) -> String? {
        guard sourceIsStale else { return nil }
        guard let installedRaw = installed?.trimmingCharacters(in: .whitespacesAndNewlines),
              !installedRaw.isEmpty,
              let stagedParts = parse(staged.trimmingCharacters(in: .whitespacesAndNewlines)),
              let installedParts = parse(installedRaw)
        else { return nil }
        guard compare(stagedParts, installedParts) == .orderedSame else { return nil }
        return "소스가 설치본보다 최신인데 마케팅 \(staged.trimmingCharacters(in: .whitespacesAndNewlines)) 이 같다. "
            + "스토어/외부 표시를 올릴 때만 set-version. 로컬 freshness ship 은 epoch 만 올린다."
    }

    /// 공개 Sparkle 피드보다 마케팅이 작거나 빌드가 새지 않으면 거절.
    public static func refuseIfBehindPublished(
        stagedMarketing: String,
        stagedBuild: String,
        publishedMarketing: String,
        publishedBuild: String
    ) -> String? {
        if let why = refuseIfNotAscending(staged: stagedMarketing, installed: publishedMarketing) {
            return "공개 Sparkle 피드(\(publishedMarketing) / \(publishedBuild))보다 마케팅이 작다. \(why)"
        }
        let staged = stagedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        let published = publishedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stagedNumber = Int(staged), let publishedNumber = Int(published) else { return nil }
        guard stagedNumber > publishedNumber else {
            return "공개 Sparkle 피드 빌드 \(publishedNumber) 보다 새지 않다(스테이지 \(stagedNumber))."
        }
        return nil
    }

    static func compare(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> ComparisonResult {
        if a.0 != b.0 { return a.0 < b.0 ? .orderedAscending : .orderedDescending }
        if a.1 != b.1 { return a.1 < b.1 ? .orderedAscending : .orderedDescending }
        if a.2 != b.2 { return a.2 < b.2 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
