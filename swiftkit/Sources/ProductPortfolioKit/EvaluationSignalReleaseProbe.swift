import Foundation

/// 설치본 codesign / stapler 관측. 실패·타임아웃은 nil(미스캔).
enum EvaluationSignalReleaseProbe {
    static func hasHardenedRuntime(_ appURL: URL) -> Bool? {
        let output = run("/usr/bin/codesign", arguments: ["-dv", "--verbose=2", appURL.path])
        guard let output else { return nil }
        return output.contains("(runtime)")
    }

    static func isNotarized(_ appURL: URL) -> Bool? {
        // stapler validate: exit 0 = 스테이플된 공증 티켓 있음
        let result = run("/usr/bin/xcrun", arguments: ["stapler", "validate", appURL.path], timeout: 3)
        guard let result else { return nil }
        return result.status == 0
    }

    static func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval = 3
    ) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            do {
                _ = try pipe.fileHandleForReading.readToEnd()
            } catch {}
            return nil
        }

        let data: Data
        do {
            data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        } catch {
            data = Data()
        }
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    }

    static func run(_ launchPath: String, arguments: [String]) -> String? {
        run(launchPath, arguments: arguments, timeout: 3)?.output
    }
}
