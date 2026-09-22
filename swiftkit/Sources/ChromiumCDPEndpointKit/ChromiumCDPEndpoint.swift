import Foundation

/// Chromium CDP(Chrome DevTools Protocol) 엔드포인트 발견.
///
/// `--remote-debugging-port=0`으로 시작 시 Chromium은 `<user-data-dir>/DevToolsActivePort` 파일에
/// 할당된 loopback 포트를 씁니다. 파일 형식: "PORT\nWS_PATH" (첫 줄 포트, 둘째 줄 WebSocket 경로).
/// Phase A: 포트 발견만 — CDP 클라이언트/eval/필터는 다음 Phase.
///
/// 보안 주의:
/// - 포트 0 = OS가 랜덤 loopback 포트 할당, 외부 바인딩 금지 (Chromium 기본 동작).
/// - 이 포트 자체 노출 위험은 낮지만, eval 이후 단계에서 credential 필터가 필수임.
/// - Phase A는 포트 발견만 하며, 실제 CDP 연결은 Phase B 이후.
public enum ChromiumCDPEndpoint {

    /// DevToolsActivePort 파일 경로.
    public static func devToolsActivePortURL(profileURL: URL) -> URL {
        profileURL.appendingPathComponent("DevToolsActivePort")
    }

    /// DevToolsActivePort 파일에서 CDP 포트를 읽습니다.
    ///
    /// 파일이 없거나 형식이 잘못되면 nil을 반환합니다 (CDP 미발견).
    /// 파일 형식: "PORT\nWS_PATH" (첫 줄 포트, 둘째 줄 WebSocket 경로).
    ///
    /// - Parameter profileURL: Chromium 프로필 URL (user-data-dir).
    /// - Returns: CDP 포트 (nil = 파일 없음 또는 읽기 실패).
    public static func readCDPPort(from profileURL: URL) -> Int? {
        let fileURL = devToolsActivePortURL(profileURL: profileURL)
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return nil
        }
        let lines = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard let portLine = lines.first else { return nil }
        let portString = portLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(portString)
    }
}
