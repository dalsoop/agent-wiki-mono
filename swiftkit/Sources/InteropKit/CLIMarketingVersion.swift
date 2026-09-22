import Foundation

/// CLI 가 말하는 마케팅 버전. Helpers 바이너리 `Bundle.main` 은 스텁 `0.1.0` 인
/// 경우가 많아, 심링크를 풀어 호스트 `.app/Contents/Info.plist` 를 본다.
public enum CLIMarketingVersion {
    public static func isStub(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty || v == "0" || v.hasPrefix("0.")
    }

    public static func fromPlist(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let raw = values["CFBundleShortVersionString"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func resolve(processPath: String, mainShortVersion: String?) -> String {
        // Helpers 바이너리 Bundle.main 은 스캐폴드 `1.0.0` 인 경우가 많다.
        // 호스트 .app Info.plist 가 있으면 그걸 먼저 쓴다.
        let dir = URL(fileURLWithPath: processPath).resolvingSymlinksInPath()
            .deletingLastPathComponent()
        if dir.lastPathComponent == "Helpers" {
            let plist = dir.deletingLastPathComponent().appendingPathComponent("Info.plist")
            if let v = fromPlist(at: plist), !v.isEmpty { return v }
        }
        if let main = mainShortVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !isStub(main) {
            return main
        }
        if let main = mainShortVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !main.isEmpty {
            return main
        }
        return "1.0.0"
    }

    public static func current() -> String {
        resolve(
            processPath: Bundle.main.executablePath ?? CommandLine.arguments[0],
            mainShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    public static func printLine(name: String) {
        print("\(name) \(current())")  // allow:debug — CLI marketing version stamp
    }
}
