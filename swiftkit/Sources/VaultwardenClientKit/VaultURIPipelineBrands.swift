import Foundation

private struct VaultURIBrand {
    var needle: String
    var uri: String
}

private let vaultURIBrands: [VaultURIBrand] = [
    VaultURIBrand(needle: "원티드", uri: "https://www.wanted.co.kr"),
    VaultURIBrand(needle: "wanted", uri: "https://www.wanted.co.kr"),
    VaultURIBrand(needle: "리그오브레전드", uri: "https://www.leagueoflegends.com"),
    VaultURIBrand(needle: "leagueoflegends", uri: "https://www.leagueoflegends.com"),
    VaultURIBrand(needle: "굿웨어몰", uri: "https://www.goodwearmall.com"),
    VaultURIBrand(needle: "디자인돌", uri: "https://terawell.net/ko/"),
    VaultURIBrand(needle: "designdoll", uri: "https://terawell.net/ko/"),
    VaultURIBrand(needle: "모셔니스트", uri: "https://motionist.kr"),
    VaultURIBrand(needle: "비즈프린트", uri: "https://biz.photomon.com"),
    VaultURIBrand(needle: "앵글나라", uri: "https://anglenara.kr"),
    VaultURIBrand(needle: "아이피타임", uri: "https://iptime.com"),
    VaultURIBrand(needle: "iptime", uri: "https://iptime.com"),
    VaultURIBrand(needle: "axure", uri: "https://www.axure.com"),
    VaultURIBrand(needle: "ds file", uri: "https://account.synology.com"),
    VaultURIBrand(needle: "nid.naver", uri: "https://nid.naver.com"),
    VaultURIBrand(needle: "naver", uri: "https://nid.naver.com"),
    VaultURIBrand(needle: "google", uri: "https://accounts.google.com"),
    VaultURIBrand(needle: "gmail", uri: "https://accounts.google.com"),
    VaultURIBrand(needle: "github", uri: "https://github.com"),
    VaultURIBrand(needle: "gitlab", uri: "https://gitlab.com"),
    VaultURIBrand(needle: "apple", uri: "https://appleid.apple.com"),
    VaultURIBrand(needle: "icloud", uri: "https://icloud.com"),
    VaultURIBrand(needle: "microsoft", uri: "https://login.microsoftonline.com"),
    VaultURIBrand(needle: "outlook", uri: "https://login.live.com"),
    VaultURIBrand(needle: "kakao", uri: "https://accounts.kakao.com"),
    VaultURIBrand(needle: "daum", uri: "https://logins.daum.net"),
    VaultURIBrand(needle: "coupang", uri: "https://www.coupang.com"),
    VaultURIBrand(needle: "figma", uri: "https://www.figma.com"),
    VaultURIBrand(needle: "slack", uri: "https://slack.com"),
    VaultURIBrand(needle: "notion", uri: "https://www.notion.so"),
    VaultURIBrand(needle: "openai", uri: "https://chatgpt.com"),
    VaultURIBrand(needle: "chatgpt", uri: "https://chatgpt.com"),
    VaultURIBrand(needle: "anthropic", uri: "https://claude.ai"),
    VaultURIBrand(needle: "claude", uri: "https://claude.ai"),
    VaultURIBrand(needle: "x.ai", uri: "https://console.x.ai"),
    VaultURIBrand(needle: "grok", uri: "https://grok.x.ai"),
    VaultURIBrand(needle: "cursor", uri: "https://cursor.com"),
    VaultURIBrand(needle: "cloudflare", uri: "https://dash.cloudflare.com"),
    VaultURIBrand(needle: "aws", uri: "https://console.aws.amazon.com"),
    VaultURIBrand(needle: "amazon", uri: "https://www.amazon.com"),
    VaultURIBrand(needle: "steam", uri: "https://store.steampowered.com"),
    VaultURIBrand(needle: "discord", uri: "https://discord.com"),
    VaultURIBrand(needle: "facebook", uri: "https://www.facebook.com"),
    VaultURIBrand(needle: "instagram", uri: "https://www.instagram.com"),
    VaultURIBrand(needle: "youtube", uri: "https://www.youtube.com"),
    VaultURIBrand(needle: "netflix", uri: "https://www.netflix.com"),
    VaultURIBrand(needle: "paypal", uri: "https://www.paypal.com"),
    VaultURIBrand(needle: "stripe", uri: "https://dashboard.stripe.com"),
    VaultURIBrand(needle: "toss", uri: "https://toss.im"),
    VaultURIBrand(needle: "kakaobank", uri: "https://www.kakaobank.com"),
    VaultURIBrand(needle: "shinhan", uri: "https://www.shinhan.com"),
    VaultURIBrand(needle: "kbcard", uri: "https://card.kbcard.com"),
    VaultURIBrand(needle: "kbstar", uri: "https://www.kbstar.com"),
    VaultURIBrand(needle: "hometax", uri: "https://hometax.go.kr"),
    VaultURIBrand(needle: "홈택스", uri: "https://hometax.go.kr"),
    VaultURIBrand(needle: "gov.kr", uri: "https://www.gov.kr"),
    VaultURIBrand(needle: "synology", uri: "https://account.synology.com"),
    VaultURIBrand(needle: "proxmox", uri: "https://proxmox.com"),
    VaultURIBrand(needle: "cloudflare", uri: "https://dash.cloudflare.com"),
    VaultURIBrand(needle: "vercel", uri: "https://vercel.com"),
    VaultURIBrand(needle: "npmjs", uri: "https://www.npmjs.com"),
    VaultURIBrand(needle: "docker", uri: "https://hub.docker.com"),
    VaultURIBrand(needle: "atlassian", uri: "https://id.atlassian.com"),
    VaultURIBrand(needle: "jira", uri: "https://id.atlassian.com"),
    VaultURIBrand(needle: "adobe", uri: "https://account.adobe.com"),
    VaultURIBrand(needle: "dropbox", uri: "https://www.dropbox.com"),
    VaultURIBrand(needle: "zoom", uri: "https://zoom.us"),
    VaultURIBrand(needle: "linkedin", uri: "https://www.linkedin.com"),
    VaultURIBrand(needle: "twitter", uri: "https://x.com"),
    VaultURIBrand(needle: "x.com", uri: "https://x.com"),
]

extension VaultURIPipeline {
    public static func proposeFill(for item: VaultItem) -> (uri: String, reason: String)? {
        guard loginNeedsURI(item) else { return nil }
        return proposeFromName(item)
    }

    /// 기존 주소가 깨져 있어도 이름으로 사이트를 찾는다.
    public static func proposeFromName(_ item: VaultItem) -> (uri: String, reason: String)? {
        let search = brandSearchText(for: item)
        let lowered = search.lowercased()
        for brand in vaultURIBrands {
            if lowered.contains(brand.needle) {
                return (brand.uri, "이름 \(brand.needle)")
            }
        }
        if let extracted = extractURL(from: search) {
            return (extracted, "이름·메모에서 주소 추출")
        }
        return nil
    }

    public static func applyDrafts(_ snapshot: Snapshot, drafts: [String: String]) -> Snapshot {
        var next = snapshot
        next.rows = snapshot.rows.map { row in
            var copy = row
            if let draft = drafts[row.itemID] {
                let uris = normalizedURIList(draft)
                if !uris.isEmpty {
                    copy.proposedURI = uris.joined(separator: "\n")
                    if copy.reason.contains("직접 입력") || copy.reason.isEmpty {
                        copy.reason = "직접 입력"
                    }
                }
            }
            return copy
        }
        return next
    }

    public static func unionURIs(_ lists: [String]...) -> [String] {
        normalizedURIList(lists.flatMap { $0 }.joined(separator: "\n"))
    }

    static func brandSearchText(for item: VaultItem) -> String {
        stripEmails([VaultBracketName.displayBody(from: item.name), item.notes].joined(separator: " "))
    }

    static func stripEmails(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            with: " ",
            options: .regularExpression
        )
    }

    static func extractURL(from text: String) -> String? {
        if let match = text.range(
            of: #"https?://[^\s,;]+"#,
            options: .regularExpression
        ) {
            let value = String(text[match]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
            if !isBlankURI(value) { return value }
        }
        if let match = text.range(
            of: #"(?<![@\w])(?:www\.)?[a-z0-9][a-z0-9.-]+\.(?:com|net|org|io|kr|co\.kr|ai|app|dev|gg|me)(?:/[^\s]*)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return normalizedURI(String(text[match]))
        }
        return nil
    }
}
