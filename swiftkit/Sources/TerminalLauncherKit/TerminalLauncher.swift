import Foundation

/// 보이는 터미널 창에서 셸 명령을 실행한다 — 3-OS 공용 API.
///
/// - macOS: `.command` 파일을 만들어 `/usr/bin/open` 한다.
/// - Linux: `$TERMINAL` → `x-terminal-emulator` → 알려진 에뮬레이터 순으로 찾아 `-e` 로 실행.
/// - Windows: Windows Terminal(`wt`)이 있으면 사용, 없으면 `cmd /k`.
///
/// 알림은 `NotificationKit` 을, 앱 활성화는 `NSWorkspace` 를 써라.
public enum TerminalLauncher {
    /// 셸/파일 경로에 넣기 위한 이스케이프(역슬래시·큰따옴표).
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 주어진 셸 명령을 새 터미널 창에서 실행(가능하면 창 활성화 포함). 성공 여부 반환.
    /// 주의: `command` 는 신뢰 가능한 값이어야 한다(이스케이프는 문자열 안전화일 뿐 셸 인젝션
    /// 방지가 아니다 — 터미널이 셸로 그대로 실행한다). 사용자 입력은 호출부가 검증할 것.
    ///
    /// `runner` 는 테스트 주입용. 기본값은 OS별 정본 실행기다.
    @discardableResult
    public static func run(_ command: String, runner: ((String) -> Bool)? = nil) -> Bool {
        #if os(macOS)
        return (runner ?? TerminalLauncher.openCommandFile)(command)
        #elseif os(Linux)
        return (runner ?? TerminalLauncher.linuxRunner)(command)
        #elseif os(Windows)
        return (runner ?? TerminalLauncher.windowsRunner)(command)
        #else
        return false
        #endif
    }

    /// macOS: 실행할 `.command` 파일 본문. 테스트 관측 지점.
    public static func commandFileContents(for command: String) -> String {
        "#!/bin/zsh\n\(command)\n"
    }

    #if os(macOS)
    /// `.command` 를 임시 폴더에 쓰고 `open` 한다. 기본 터미널(또는 .command 연결 앱)이 연다.
    public static func openCommandFile(_ command: String) -> Bool {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("terminal-\(UUID().uuidString).command")
        do {
            try commandFileContents(for: command).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return false
        }
        return spawn("/usr/bin/open", [url.path])
    }
    #endif

    #if os(Linux)
    static let linuxCandidates = [
        "x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal",
        "alacritty", "kitty", "xterm",
    ]

    static func linuxRunner(_ command: String) -> Bool {
        let names: [String] = {
            if let env = ProcessInfo.processInfo.environment["TERMINAL"], !env.isEmpty {
                return [env] + linuxCandidates
            }
            return linuxCandidates
        }()
        for name in names {
            if spawn("/usr/bin/env", [name, "-e", "sh", "-c", command]) { return true }
        }
        return false
    }
    #endif

    #if os(Windows)
    static func windowsRunner(_ command: String) -> Bool {
        if spawn("wt.exe", ["cmd", "/k", command]) { return true }
        return spawn("cmd.exe", ["/c", "start", "cmd", "/k", command])
    }
    #endif

    static func spawn(_ launch: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        do { try p.run(); return true } catch { return false }
    }
}
