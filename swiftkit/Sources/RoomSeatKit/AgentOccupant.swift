import Foundation

/// 방 체제 occupant 핸들의 정본 조립. hostName API 접근은 이 한 곳에서만 한다.
/// room-terminal·room-monitor 는 이 정본을 쓴다(identity-single-source).
/// 형제 앱 직접 결합이 금지되므로(package-manifest-static) 공유는 RoomKit 로만 한다.
public enum AgentOccupant {
    /// 방 표기용 짧은 호스트 라벨(첫 접두 라벨, 빈 라벨이면 "host").
    /// 대소문자 정규화는 호출자의 표기 관습에 맡긴다.
    public static func shortHost(_ host: String = ProcessInfo.processInfo.hostName) -> String {
        let label = host.split(separator: ".").first.map(String.init) ?? host
        return label.isEmpty ? "host" : label
    }
}
