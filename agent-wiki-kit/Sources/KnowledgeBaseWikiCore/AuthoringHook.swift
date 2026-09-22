import Foundation

/// 하네스 훅 payload → `~/.agent-wiki/authoring.json`.
///
/// 읽는 쪽(`Authoring.ambient`)은 진작 이 앱에 있었는데 **쓰는 쪽만 셸 스크립트**로
/// 밖에 나가 있었다(`~/.codex/tools/agent-wiki-authoring-hook.sh` — bash 가 python3 를
/// 부르고 python 이 JSON 을 쓰는 3단 구조). 원장 저작 조건은 이 앱의 소유물이므로
/// 여기 있어야 한다. 훅 명령은 스크립트가 아니라 `agent-wiki hook authoring` 이다.
///
/// ## 규약 (스크립트가 지키던 것을 그대로 승계한다)
///
/// - **절대 세션을 막지 않는다.** 무슨 일이 있어도 성공으로 끝난다. 훅이 실패하면
///   하네스 세션이 멈추므로, 파싱 실패·권한 문제도 조용히 넘긴다.
/// - 네트워크·무거운 작업 없음. stdin 한 번 읽고 파일 하나 쓴다.
/// - **아는 것만 적는다.** 없는 값을 0 이나 빈 문자열로 채우지 않는다 — 그러면
///   "모른다" 와 "0 이다" 가 구분되지 않는다.
/// - 원자적 교체. 발행 중인 CLI 가 반쯤 쓰인 파일을 읽으면 안 된다.
public enum AuthoringHook {
    /// 훅 payload 에서 저작 조건을 뽑는다. 하네스마다 키 이름이 달라 후보를 순서대로 본다.
    public static func authoring(fromEventJSON data: Data,
                                 hostName: String = ProcessInfo.processInfo.hostName)
        -> Authoring
    {
        let event: [String: Any]
        do {
            event = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            event = [:]
        }

        func pick(_ keys: String...) -> String? {
            for key in keys {
                guard let value = event[key] as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return nil
        }

        return Authoring(
            runtime: pick("source", "runtime") ?? "claude-code",
            model: pick("model", "model_id", "modelId"),
            session: pick("session_id", "sessionId"),
            host: hostName)
    }

    /// 저작 조건을 배경 파일에 원자적으로 남긴다. 실패해도 던지지 않는다 — 훅은 조용해야 한다.
    @discardableResult
    public static func write(_ authoring: Authoring, to url: URL = Authoring.ambientPath) -> Bool {
        guard let line = authoring.jsonLine else { return false }
        let directory = url.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { _ = error }

        // `.tmp` 로 쓰고 교체 — 발행 중인 CLI 가 반쯤 쓰인 파일을 읽지 않게.
        let temporary = url.appendingPathExtension("tmp")
        guard (try? Data(line.utf8).write(to: temporary, options: .atomic)) != nil else {
            return false
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
    }

    /// 훅 진입점. stdin 을 읽어 파일을 남긴다. **항상 성공으로 끝난다.**
    ///
    /// 경로 기본값은 `Authoring.ambientPath` 이고 그건 `homeDirectoryForCurrentUser` 라
    /// **`HOME` 환경변수를 무시한다.** `HOME=/tmp/... ` 로 시험하면 실제 홈 파일을
    /// 덮어쓴다(실측으로 한 번 덮었다). 테스트는 반드시 `url:` 을 명시해서 부른다.
    public static func run(input: FileHandle = .standardInput,
                           url: URL = Authoring.ambientPath) {
        let data = (try? input.readToEnd()) ?? Data()
        guard !data.isEmpty else { return }
        write(authoring(fromEventJSON: data), to: url)
    }
}
