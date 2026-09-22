import Foundation

/// 한 앱에서 시작된 작업이 **다른 앱**으로 넘어갈 때, 그 출처를 되짚는 참조.
///
/// 오케스트레이션 스택의 열린 간선("대화 ↔ 일")을 닫는다 — `agent-chat` 방의 한마디가
/// `agent-worker-orchestrator` 의 JobSpec 이 되면, 그 잡이 **어느 방·어느 메시지에서
/// 왔는지** 를 잡이 스스로 들고 다닌다. 잡이 돌면서 상태가 바뀌면 출처 앱이 이 참조로
/// 역류 말풍선을 정확한 방·스레드에 붙인다. 인터op 계약이 데몬·RPC·소켓을 금지하므로,
/// 출처는 파일 기반 typed edge(StateMirror) 가 양쪽에 공유하는 **유일한 단서**다.
///
/// InteropKit 의 다른 타입(`AgentCard` 등)과 같이 기본 Codable(camelCase) 을 쓴다 —
/// 출처 앱이 인코딩하고 도착 앱이 디코딩할 때 같은 키 이름으로 만나야 한다.
public struct OriginRef: Codable, Equatable, Sendable {
    /// 출처 앱의 식별자(StateMirror 키와 같은 형태). 예: `"agent-chat"`.
    public var app: String
    /// 출처 앱 안의 방/문맥 id. 역류 말풍선을 붙일 방이다.
    public var roomID: String
    /// 잡을 촉발한 메시지 id. 역류 말풍선의 `replyTo` 가 된다.
    public var messageID: String
    /// 촉발 메시지 자체가 답장이면 그 부모 id. 스레드 뿌리를 잇는 데 쓴다(없으면 nil).
    public var replyTo: String?

    public init(app: String, roomID: String, messageID: String, replyTo: String? = nil) {
        self.app = app
        self.roomID = roomID
        self.messageID = messageID
        self.replyTo = replyTo
    }
}
