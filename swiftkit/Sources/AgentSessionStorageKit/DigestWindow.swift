import Foundation

/// 세션 파일에서 **얼마나 읽을지**.
///
/// 팩이 필요로 하는 건 대부분 "마지막 N개" 다 — 최근 지시·마지막 계획·최근 명령·마지막 발언.
/// 예외는 **최초 사용자 지시(원래 목표)** 하나뿐이고 그건 파일 머리에 있다.
/// 그래서 머리 조금 + 꼬리 한 창만 읽으면 팩의 거의 전부가 나온다.
///
/// 앞서 "JSON 파싱 전에 바이트로 거르기" 를 시도했다가 **이득이 없어 되돌렸다** — 파싱하는
/// 바이트 총량이 그대로였기 때문이다(실측 1.58s vs 1.49s). 이번엔 총량 자체를 줄인다.
public enum DigestWindow: Sendable, Equatable {
    /// 파일 전체. 포맷 드리프트 감지(`doctor`)처럼 빠짐없이 봐야 할 때.
    case full
    /// 머리 `head` 바이트 + 꼬리 `tail` 바이트.
    case recent(head: Int, tail: Int)

    /// 이 창이 내용을 잘라낼 수 있는가. `.full` 은 아니다.
    public var isTruncating: Bool {
        if case .full = self { return false }
        return true
    }

    /// 화면·팩 생성 기본값. 큰 세션에서 체감이 크고, 작은 파일은 어차피 전체를 읽는다.
    public static let standard = DigestWindow.recent(head: 256 * 1024, tail: 8 * 1024 * 1024)

    /// 이 파일에 대해 실제로 읽을 구간. 파일이 창보다 작으면 전체 한 번으로 끝낸다
    /// (머리·꼬리가 겹쳐 같은 줄을 두 번 세는 것을 막는다).
    public func plan(fileSize: Int) -> Plan {
        switch self {
        case .full:
            return .whole
        case let .recent(head, tail):
            guard fileSize > head + tail else { return .whole }
            return .headAndTail(headBytes: head, tailOffset: fileSize - tail)
        }
    }

    public enum Plan: Sendable, Equatable {
        case whole
        case headAndTail(headBytes: Int, tailOffset: Int)

        public var isTruncated: Bool {
            if case .headAndTail = self { return true }
            return false
        }
    }
}
