import DoctorContract
import Foundation
import InteropKit

/// `version` · `--version` · `capabilities --json` 의 version 칸이 호스트 마케팅 버전인지.
///
/// 같은 프로세스의 `CLIMarketingVersion.current()` 만 보면 하드코딩 `print` 를
/// 못 잡는다. PATH 바이너리를 돌려 사용자가 보는 줄을 본다.
public struct CLIMarketingVersionProvider: DoctorProvider {
    public let id = "cli-marketing-version"
    private let cliName: String
    private let isExecutable: @Sendable (String) -> Bool
    private let marketingVersion: @Sendable (String) -> String
    private let runCommand: @Sendable (String, [String]) -> String?

    public init(
        cliName: String,
        isExecutable: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        },
        marketingVersion: @escaping @Sendable (String) -> String = { processPath in
            CLIMarketingVersion.resolve(processPath: processPath, mainShortVersion: nil)
        },
        runVersion: (@Sendable (String) -> String?)? = nil,
        runCommand: (@Sendable (String, [String]) -> String?)? = nil
    ) {
        self.cliName = cliName
        self.isExecutable = isExecutable
        self.marketingVersion = marketingVersion
        if let runCommand {
            self.runCommand = runCommand
        } else if let runVersion {
            self.runCommand = { executable, args in
                args == ["version"] ? runVersion(executable) : nil
            }
        } else {
            self.runCommand = { executable, args in
                Self.capture(executable: executable, arguments: args)
            }
        }
    }

    public func run() async -> [DoctorFinding] {
        let home = NSHomeDirectory()
        let candidates = [
            HostPlatform.cliBinPath(cliName),
            "/usr/local/bin/\(cliName)",
            (home as NSString).appendingPathComponent(".local/bin/\(cliName)"),
        ]
        guard let executable = candidates.first(where: { isExecutable($0) }) else {
            return []
        }
        let expected = marketingVersion(executable)
        var out: [DoctorFinding] = []
        out.append(contentsOf: checkTextStamp(
            label: "version",
            expected: expected,
            output: runCommand(executable, ["version"]),
            required: true,
            executable: executable
        ))
        out.append(contentsOf: checkTextStamp(
            label: "--version",
            expected: expected,
            output: runCommand(executable, ["--version"]),
            required: false,
            executable: executable
        ))
        out.append(contentsOf: checkCapabilities(
            expected: expected,
            output: runCommand(executable, ["capabilities", "--json"])
        ))
        return out
    }

    private func checkTextStamp(
        label: String,
        expected: String,
        output: String?,
        required: Bool,
        executable: String
    ) -> [DoctorFinding] {
        guard let output else {
            if required {
                return [finding(
                    title: "\(label) 명령을 못 돌렸다",
                    detail: executable,
                    remedy: "\(cliName) \(label) 이 5초 안에 끝나는지 확인"
                )]
            }
            return []
        }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !required && Self.looksUnsupported(text) { return [] }
        if text.contains("helpers-cli") {
            return [finding(
                title: "\(label) 이 helpers-cli 자리표기를 찍는다",
                detail: text,
                remedy: "CLIMarketingVersion.printLine(name:) 또는 current()"
            )]
        }
        if expected.isEmpty || !text.contains(expected) {
            return [finding(
                title: "\(label) 이 마케팅 버전과 다르다",
                detail: "기대 \(expected) / 출력 \(text)",
                remedy: "Info.plist CFBundleShortVersionString 을 CLIMarketingVersion 으로 찍어라"
            )]
        }
        return []
    }

    private func checkCapabilities(expected: String, output: String?) -> [DoctorFinding] {
        guard let output else { return [] }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksUnsupported(text) { return [] }
        if text.contains("helpers-cli") {
            return [finding(
                title: "capabilities version 이 helpers-cli 자리표기다",
                detail: text,
                remedy: "Capabilities 이니셜라이저에서 version 인자를 생략하라"
            )]
        }
        guard let field = Self.capabilitiesVersion(from: text) else {
            return [finding(
                title: "capabilities JSON 에 version 칸이 없다",
                detail: String(text.prefix(240)),
                remedy: "capabilities --json 의 result.version 을 마케팅 버전으로 채워라"
            )]
        }
        if expected.isEmpty || field != expected {
            return [finding(
                title: "capabilities version 이 마케팅 버전과 다르다",
                detail: "기대 \(expected) / 칸 \(field)",
                remedy: "Capabilities 이니셜라이저에서 version 인자를 생략하라"
            )]
        }
        return []
    }

    private func finding(title: String, detail: String, remedy: String) -> DoctorFinding {
        DoctorFinding(
            category: .runtime,
            severity: .fail,
            body: .init(
                subject: cliName,
                title: title,
                detail: detail,
                remedy: remedy
            ),
            source: id,
            checkKind: .behavioral
        )
    }

    static func looksUnsupported(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("알 수 없는 옵션")
            || t.contains("알 수 없는 명령")
            || t.contains("unknown option")
            || t.contains("unknown flag")
            || t.contains("unknown command")
            || t.contains("unexpected argument")
            || t.contains("unrecognized option")
    }

    static func capabilitiesVersion(from text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        guard let dict = obj as? [String: Any] else { return nil }
        if let result = dict["result"] as? [String: Any],
           let version = result["version"] as? String {
            return version
        }
        if let version = dict["version"] as? String {
            return version
        }
        return nil
    }

    static func capture(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = CLIMarketingVersionStampConstants.captureTimeout
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            finished.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
