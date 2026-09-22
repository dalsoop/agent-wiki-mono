import Foundation

/// 일감 언어 ↔ 도구 언어 다리 — 함대 검색(`CapabilitySearcher`)의 토큰 확장기.
///
/// ## 왜 있나 (실측 2026-08-06)
///
/// 대표 일감 질의 40개로 함대 검색 재현율을 재니 **38%** 였다
/// (당시 표면은 `agent-work-market find`. 그 앱은 걷어냈고 지금 표면은 `agent-app-registry search` 다 —
///  둘 다 이 `CapabilitySearcher` 를 쓰므로 측정은 그대로 유효하다).
/// 원인은 둘, 둘 다 순수 부분일치의 한계다:
///
/// 1. **한↔영 어휘 불일치** — 사용자는 "스크린샷" 이라 말하고 앱은 `screenshot` 이다.
///    registry 의 summary 가 한국어라도 앱 이름·CLI·명령 이름은 영어다.
/// 2. **한국어 어미** — "찍어줘"·"정리해줘" 는 어떤 필드에도 부분일치하지 않는다.
///    (`partialMatches` 폴백도 토큰 자체가 안 걸리면 소용없다.)
///
/// 앱 267개의 summary 를 전부 일감 언어로 고치는 것보다, **여기 한 곳**에서
/// 질의 토큰을 넓히는 쪽이 싸고 유지된다. 사전은 도메인 일반어만 담는다 —
/// 특정 앱 이름을 하드코딩해 특정 앱을 밀어주지 않는다.
public enum QueryLexicon {
    /// 뜻 없는 기능어 — 어느 앱 설명에나 부분일치해 **순위를 오염**시킨다.
    /// 실측(2026-08-06): "포트 뭐가 쓰고 있어" 의 뭐가·쓰고·있어 가 아무 앱에나 걸려
    /// system-ports 가 3위로 밀렸다. AND·폴백 양쪽에서 빼되, 스톱워드만으로 된
    /// 질의는 원문 그대로 둔다(전부 빼면 빈 질의가 된다).
    public static let stopwords: Set<String> = [
        "뭐", "뭐가", "뭘", "뭐지", "뭐야", "어떤", "어떻게", "어디", "왜",
        "좀", "그냥", "지금", "빨리", "한번", "다시", "자동",
        "있어", "있지", "있나", "없어", "없나", "쓰고", "쓰는", "하는", "할", "해야",
        "봐줘", "줘봐", "보자", "그거", "이거", "저거", "관련", "대해",
        "the", "a", "an", "of", "for", "to", "in", "my",
    ]

    /// 질의 토큰에서 스톱워드를 뺀다. 전부 스톱워드면 원문 유지.
    public static func dropStopwords(_ tokens: [String]) -> [String] {
        let kept = tokens.filter { !stopwords.contains(CapabilitySearcher.normalize($0)) }
        return kept.isEmpty ? tokens : kept
    }

    /// 토큰 하나 → 그 토큰이 "걸린 것으로 칠" 변형들(자기 자신 포함, 전부 정규화됨).
    ///
    /// 변형 = 자기 자신 + 어미를 벗긴 줄기(들) + 각각의 동의어 번역.
    /// AND 판정은 토큰 단위 그대로다 — 변형은 그 토큰의 발음이 다른 같은 말일 뿐,
    /// 토큰 수를 늘려 정확도를 흐리지 않는다.
    public static func variants(_ token: String) -> [String] {
        let norm = CapabilitySearcher.normalize(token)
        guard !norm.isEmpty else { return [] }
        var out: [String] = [norm]
        var seen: Set<String> = [norm]

        func push(_ s: String) {
            let n = CapabilitySearcher.normalize(s)
            guard !n.isEmpty, seen.insert(n).inserted else { return }
            out.append(n)
        }

        // 1) 어미 벗기기 — "찍어줘" → "찍", "정리해줘" → "정리".
        var stems = [norm]
        for stem in strippedStems(norm) {
            push(stem)
            stems.append(stem)
        }
        // 2) 동의어 — 원형·줄기 각각에 대해 사전을 찾는다.
        for s in stems {
            for syn in synonyms[s] ?? [] { push(syn) }
        }
        return out
    }

    /// 한국어 조사·어미 벗기기 — 사전 기반이 아니라 **꼬리 자르기**다.
    /// 과하게 자르면 오탐이 오르므로: 줄기가 2자 미만이 되면 버리되,
    /// 동의어 사전에 있는 1자 줄기(예: "창")는 남긴다.
    static func strippedStems(_ norm: String) -> [String] {
        // 긴 꼬리 먼저 — "해줘" 를 "줘" 보다 먼저 대야 "정리" 가 남는다.
        let tails = [
            "해주세요", "해줄래", "해봐줘", "어떻게", "해야지", "합니다",
            "해줘", "해봐", "해라", "하기", "하자", "할까", "해서", "하면", "했어",
            "어줘", "아줘", "여줘", "은지", "는지",
            "해", "줘", "요", "좀", "을", "를", "이", "가", "은", "는", "의", "로", "에",
        ]
        var found: [String] = []
        var current = norm
        // 꼬리는 겹쳐 붙는다("정리해줘요") — 두 번까지 벗긴다.
        for _ in 0..<2 {
            var stripped = false
            for t in tails where current.hasSuffix(t) && current.count > t.count {
                let stem = String(current.dropLast(t.count))
                if stem.count >= 2 || synonyms[stem] != nil {
                    found.append(stem)
                    current = stem
                    stripped = true
                    break
                }
            }
            if !stripped { break }
        }
        return found
    }

    /// 일감 낱말 → 도구 낱말. **도메인 일반어만** — 앱 이름·제품명 금지.
    /// 값은 영어 원형 위주(부분일치라 어형 변화는 저절로 흡수된다).
    /// 양방향이 필요하면 양쪽에 다 적는다(영→한은 드물어 필요한 것만).
    static let synonyms: [String: [String]] = [
        // 화면·창·입출력
        "스크린샷": ["screenshot", "capture", "캡처"],
        "캡처": ["capture", "screenshot", "스크린샷"],
        "화면": ["screen", "display", "화면"],
        "창": ["window", "윈도우"],
        "녹화": ["record", "recorder", "capture"],
        "녹음": ["record", "voice", "audio", "음성"],
        "클립보드": ["clipboard"],
        "키보드": ["keyboard", "typer", "입력"],
        "입력": ["input", "typer", "type"],
        "맥": ["mac", "macos"],
        "설정": ["settings", "config", "preference"],
        "받아적어": ["scribe", "transcribe", "voice"],
        "받아적기": ["scribe", "transcribe", "voice"],
        "마우스": ["mouse", "click"],
        // 보안·계정
        "비밀번호": ["password", "credential", "secret", "vault", "자격"],
        "암호": ["password", "credential", "secret"],
        "자격증명": ["credential", "secret"],
        "권한": ["permission", "privilege", "tcc"],
        "인증서": ["cert", "certificate", "tls"],
        "계정": ["account", "identity"],
        // 개발·배포
        "배포": ["ship", "deploy", "distribution", "release", "rollout"],
        "출하": ["ship", "release"],
        "빌드": ["build", "compile"],
        "커밋": ["commit", "git"],
        "리뷰": ["review", "mr", "pr"],
        "검증": ["verify", "verifier", "audit", "validate", "check"],
        "머지": ["merge", "mr"],
        "브랜치": ["branch", "worktree", "git"],
        "테스트": ["test", "e2e", "eval"],
        "로그": ["log", "console"],
        "디버그": ["debug", "console"],
        "스킬": ["skill"],
        "승인": ["approval", "approve"],
        "세션": ["session", "replay"],
        "위키": ["wiki", "knowledge"],
        "이력": ["history", "log", "ledger", "record", "원장", "기록"],
        "아이콘": ["icon", "asset"],
        // 시스템·인프라
        "디스크": ["disk", "storage", "space"],
        "용량": ["disk", "space", "storage"],
        "포트": ["port"],
        "서버": ["server", "infra", "remote"],
        "도메인": ["domain", "dns", "zone"],
        "인그레스": ["ingress"],
        "쿠버네티스": ["kube", "kubernetes", "k8s", "helm"],
        "컨테이너": ["container", "docker"],
        "백업": ["backup", "nas", "sync"],
        "원격": ["remote", "ssh", "desktop"],
        "데스크탑": ["desktop", "remote"],
        "네트워크": ["network", "dns", "topology"],
        "모니터링": ["monitor", "status", "watch"],
        "진단": ["doctor", "health", "diagnos", "guard"],
        "상태": ["status", "health", "state"],
        "정리": ["clean", "organize", "snap", "lifecycle", "analyzer"],
        "검색": ["search", "find", "query"],
        // 사무·PIM
        "메모": ["memo", "note"],
        "노트": ["note", "memo"],
        "일정": ["calendar", "schedule", "agenda"],
        "할일": ["todo", "task"],
        "메일": ["mail", "email"],
        "연락처": ["contact", "people"],
        "문서": ["document", "doc", "pdf"],
        "영수증": ["receipt", "ocr"],
        "장부": ["ledger", "tax"],
        "번역": ["translate", "translation"],
        // 미디어
        "이미지": ["image", "picture"],
        "그림": ["image", "sprite", "draw"],
        "사진": ["image", "photo", "picture"],
        "영상": ["video", "movie", "player"],
        "동영상": ["video", "movie", "player"],
        "비디오": ["video", "movie"],
        "음성": ["voice", "audio", "scribe", "sound"],
        "소리": ["sound", "audio"],
        "자막": ["subtitle", "translate"],
        "받아적": ["scribe", "transcribe", "voice"],
        "찍어": ["capture", "screenshot", "shot", "record"],
        "찍": ["capture", "screenshot", "shot"],
        "생성": ["generate", "generation", "forge", "gen"],
        "만들": ["generate", "forge", "create", "generator", "생성", "만든다"],
        "앱": ["app", "application"],
        "기록": ["record", "publish", "log", "note", "ledger"],
        "접속": ["connect", "access", "remote", "login"],
        "잘라": ["cut", "trim", "export"],
        "자르": ["cut", "trim", "export"],
        "편집": ["edit", "editor"],
        // 브라우저·웹
        "브라우저": ["browser", "chrome", "chromium"],
        "웹": ["web", "browser", "http"],
        // 흔한 영→한 (앱 summary 가 한국어일 때)
        "screenshot": ["스크린샷", "캡처"],
        "record": ["녹화", "녹음"],
        "password": ["비밀번호", "credential", "secret"],
        "deploy": ["배포", "ship", "release"],
        "todo": ["할일"],
        "wiki": ["위키"],
    ]
}
