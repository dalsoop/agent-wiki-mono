import Foundation

/// 금고 항목 자동 분류 — 이름·URL·유형에서 태그를 뽑아내고, **이미 있는 폴더** 중
/// 맞는 곳을 제안한다.
///
/// 설계 원칙 두 가지:
/// 1. **덧붙이기만 한다.** 기존 태그를 지우지 않고, 이미 폴더가 정해진 항목은 옮기지 않는다.
///    수백 건을 한 번에 건드리는 작업이라, 사람이 손으로 해 둔 분류를 기계가 뒤집으면
///    되돌릴 방법이 없다.
/// 2. **폴더를 새로 만들지 않는다.** 금고 주인이 쓰는 폴더 이름(`금융·결제` 처럼 `·` 로
///    묶인 이름)을 세그먼트로 쪼개 태그와 맞춰 본다. 기계가 자기 분류 체계를 새로
///    들이미는 대신 이미 있는 체계에 끼워 넣는다.
///
/// 폴더 이름은 **태그로 옮겨 적지 않는다.** 실측(469건)에서 그렇게 했더니 상위 태그가 전부
/// 폴더 이름의 복사본이 됐다 — `SaaS·개발` 193건, `온프레미스·서버` 66건, `[99] 게임` 11건,
/// 심지어 `아이디없음` 까지. 태그 축이 폴더 축의 그림자가 되면 축을 둘로 나눈 의미가 없다.
/// 폴더는 사이드바에 이미 자기 축으로 있다.
public enum VaultClassifier {
    /// 한 항목에 대한 제안 — 무엇을 왜 바꾸려는지까지 담는다(적용 전 사람이 검토할 수 있게).
    public struct Proposal: Sendable, Equatable, Identifiable {
        public var id: String { itemID }
        public var itemID: String
        public var itemName: String
        public var currentTags: [String]
        public var proposedTags: [String]
        /// 폴더를 옮길 때만 값이 있다(이름). 이미 폴더가 있으면 항상 nil.
        public var proposedFolderID: String?
        public var proposedFolderName: String?
        /// 태그가 어디서 나왔는지 — "이름 [게임]", "주소 steam.com" 처럼.
        public var reasons: [String]

        public var addedTags: [String] {
            let existing = Set(currentTags)
            return proposedTags.filter { !existing.contains($0) }
        }

        public var isChange: Bool { !addedTags.isEmpty || proposedFolderID != nil }
    }

    /// 태그 하나를 뽑아내는 규칙. 주소(호스트)나 이름 안의 단어가 맞으면 태그를 단다.
    struct Rule {
        var tag: String
        var hosts: [String] = []
        var words: [String] = []
    }

    /// 규칙표 — 한국 실사용 서비스 중심. 새 태그가 필요하면 여기에 한 줄 더한다.
    ///
    /// **변별력 없는 태그는 넣지 않는다.** `계정` 규칙(google·naver·kakao·로그인 …)을
    /// 넣었더니 469건 중 187건에 붙었다 — 비밀번호 금고의 항목은 원래 다 계정이라,
    /// 절반에 붙는 태그는 무엇도 걸러내지 못하면서 태그 목록만 채운다.
    static let rules: [Rule] = [
        Rule(tag: "금융", hosts: ["shinhan", "kbstar", "kbcard", "hyundaicard", "samsungcard",
                                 "wooribank", "wooricard", "nonghyup", "nhbank", "ibk", "kakaobank",
                                 "kbanknow", "tossbank", "hanabank", "hanacard", "lottecard",
                                 "citibank", "sc.co.kr", "koreainvestment", "miraeasset", "kiwoom"],
             words: ["은행", "뱅크", "bank", "카드", "card", "증권", "보험", "적금", "대출"]),
        Rule(tag: "결제", hosts: ["toss", "kakaopay", "naverpay", "payco", "paypal", "stripe",
                                 "paddle", "lemonsqueezy", "danal", "inicis", "nicepay", "portone"],
             words: ["페이", "pay", "결제", "billing", "checkout"]),
        Rule(tag: "개발", hosts: ["github", "gitlab", "bitbucket", "npmjs", "pypi", "docker",
                                 "jetbrains", "sentry", "figma", "vercel", "netlify", "circleci",
                                 "sonarcloud", "codecov", "atlassian", "jira", "confluence"],
             words: ["git", "repo", "ci", "레지스트리", "registry"]),
        Rule(tag: "클라우드", hosts: ["aws.amazon", "amazonaws", "console.aws", "cloud.google",
                                    "azure", "microsoftonline", "vultr", "linode", "digitalocean",
                                    "oraclecloud", "ncloud", "cloudflare", "heroku", "fly.io",
                                    "supabase", "railway"],
             words: ["cloud", "클라우드", "vps"]),
        Rule(tag: "서버", hosts: ["cafe24", "gabia", "hosting", "namecheap", "godaddy", "hostinger",
                                 "proxmox", "synology", "qnap", "truenas"],
             words: ["서버", "server", "nas", "호스팅", "도메인", "vpn", "ssh", "루트", "root"]),
        Rule(tag: "AI", hosts: ["openai", "anthropic", "claude.ai", "x.ai", "groq", "together.ai",
                               "huggingface", "perplexity", "midjourney", "elevenlabs", "replicate",
                               "cursor.", "mistral", "deepseek"],
             words: ["gpt", "llm", "ai ", "에이아이"]),
        Rule(tag: "구독", hosts: ["netflix", "youtube", "spotify", "disneyplus", "wavve", "tving",
                                 "watcha", "coupangplay", "notion.so", "slack", "adobe", "dropbox",
                                 "melon", "genie", "bugs", "apple.com/subscribe"],
             words: ["구독", "멤버십", "premium", "plus 요금"]),
        Rule(tag: "쇼핑", hosts: ["coupang", "gmarket", "11st", "auction.co.kr", "ssg.com",
                                 "lotteon", "wemakeprice", "tmon", "aliexpress", "amazon.",
                                 "musinsa", "oliveyoung", "kurly", "temu"],
             words: ["쇼핑", "구매", "주문", "store", "shop", "마켓"]),
        Rule(tag: "게임", hosts: ["steampowered", "epicgames", "battle.net", "riotgames", "nexon",
                                 "blizzard", "nintendo", "playstation", "xbox", "gog.com",
                                 "pmang", "hangame"],
             words: ["게임", "game", "런처"]),
        Rule(tag: "통신", hosts: ["tworld", "skt", "kt.com", "lguplus", "uplus", "mobile.kt",
                                 "sktelecom", "moyoplan", "hellomobile"],
             words: ["통신", "요금제", "알뜰폰", "유심", "인터넷 가입"]),
        Rule(tag: "정부·공공", hosts: ["go.kr", "gov.kr", "hometax", "nts.go", "or.kr",
                                     "4insure", "minwon", "gov24", "wetax", "nhis"],
             words: ["국세", "세무", "홈택스", "정부", "공공", "민원", "보험공단", "사업자등록",
                     "통신판매", "지자체"]),
        Rule(tag: "라이센스", hosts: ["setapp", "paddle.com", "fastspring", "gumroad"],
             words: ["라이센스", "라이선스", "license", "시리얼", "serial", "제품키", "정품"]),
        Rule(tag: "구직", words: ["채용", "구직", "이력서", "잡코리아", "사람인", "원티드", "링크드인"]),
        Rule(tag: "업무", hosts: ["zoom.us", "webex", "teams.microsoft", "asana", "trello",
                                 "monday.com", "linear.app"],
             words: ["회사", "업무", "사내", "협업"]),
    ]

    /// 항목 유형에서 바로 나오는 태그(카드·신원·메모).
    public static func typeTag(_ type: Int) -> String? {
        switch type {
        case 2: "메모"
        case 3: "카드"
        case 4: "신원"
        default: nil
        }
    }

    /// 이름 앞의 `[게임]` 같은 대괄호 표기 — 금고 주인이 직접 붙인 분류라 가장 신뢰한다.
    public static func bracketTags(in name: String) -> [String] {
        var found: [String] = []
        var current: String?
        for character in name {
            switch character {
            case "[", "【", "(":
                current = ""
            case "]", "】", ")":
                if let value = current?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
                   value.count <= 12, !found.contains(value),
                   // 숫자만 있는 표기([99] 같은 정렬용 접두)는 분류가 아니다.
                   value.contains(where: { !$0.isNumber && !$0.isPunctuation }) {
                    found.append(value)
                }
                current = nil
            default:
                current?.append(character)
            }
        }
        return found
    }

    /// 폴더 이름을 `·`·`/`·`,` 로 쪼갠 세그먼트. `금융·결제` → ["금융", "결제", "금융·결제"].
    static func segments(of folderName: String) -> [String] {
        let parts = folderName.split(whereSeparator: { "·/,>".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.count > 1 ? parts + [folderName] : [folderName]
    }

    private static func matches(_ rule: Rule, name: String, haystack: String) -> String? {
        for host in rule.hosts where haystack.contains(host) {
            return "주소 \(host)"
        }
        for word in rule.words where name.contains(word) {
            return "이름 \(word.trimmingCharacters(in: .whitespaces))"
        }
        return nil
    }

    /// 전체 금고에 대한 제안 목록. 바뀔 게 없는 항목은 빼고 돌려준다.
    public static func propose(items: [VaultItem], folders: [VaultFolder]) -> [Proposal] {
        var folderBySegment: [String: VaultFolder] = [:]
        for folder in folders {
            for segment in segments(of: folder.name) {
                let key = segment.lowercased()
                // 세그먼트가 겹치면 이름이 짧은 폴더가 이긴다(더 일반적인 분류).
                if let existing = folderBySegment[key], existing.name.count <= folder.name.count { continue }
                folderBySegment[key] = folder
            }
        }
        // 킷이 저장하지 못하는 유형(SSH 키 등)은 제안하지 않는다 — 적용할 수 없는 제안을
        // 목록에 올려 두면 매번 실패 건수로만 남는다.
        return items.filter { !$0.deleted && VaultCipherType.editable.contains($0.type) }
            .compactMap { item -> Proposal? in
            let name = item.name.lowercased()
            let haystack = (item.loginURIs + [item.username]).joined(separator: " ").lowercased()

            var tags = item.tags
            var reasons: [String] = []
            func add(_ tag: String, _ reason: String) {
                guard !tag.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
                else { return }
                tags.append(tag)
                reasons.append("\(tag) ← \(reason)")
            }

            for tag in bracketTags(in: item.name) { add(tag, "이름 표기 [\(tag)]") }
            for rule in rules {
                if let reason = matches(rule, name: name, haystack: haystack) { add(rule.tag, reason) }
            }
            if let tag = typeTag(item.type) { add(tag, "항목 유형") }

            var proposedFolder: VaultFolder?
            if item.folderId == nil {
                proposedFolder = tags.lazy.compactMap { folderBySegment[$0.lowercased()] }.first
            }

            let proposal = Proposal(
                itemID: item.id, itemName: item.name, currentTags: item.tags, proposedTags: tags,
                proposedFolderID: proposedFolder?.id, proposedFolderName: proposedFolder?.name,
                reasons: reasons
            )
            return proposal.isChange ? proposal : nil
        }
    }
}
