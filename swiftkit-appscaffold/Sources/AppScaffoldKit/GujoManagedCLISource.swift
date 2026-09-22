import Foundation

/// CLI dual-entry 소스 경로 판정.
///
/// `GujoManagedAdoption` 에 두면 타입 분기 합이 한도를 넘는다 — 경로 휴리스틱만 여기로 뺀다.
enum GujoManagedCLISource {
    /// CLI dual-entry 소스인가.
    /// - `*CLI` / `*CTL` / `*CommandLine` 타깃 디렉터리 (대소문자 무시)
    /// - interop `cli` 이름·basename 과 같거나 `{cli}-cli` / compact 형태
    /// - package-identity `gui_product` 가 `*App` 이면 stem 폴더는 CLI 제품
    /// - Entry.swift / *CLI.swift / AXORCMain.swift
    static func isCLISource(_ url: URL, cliName: String? = nil) -> Bool {
        let comps = url.pathComponents
        if comps.contains(where: { name in
            let lower = name.lowercased()
            return lower.hasSuffix("cli")
                || lower.hasSuffix("ctl")
                || lower.hasSuffix("commandline")
        }) {
            return true
        }
        let base = url.deletingPathExtension().lastPathComponent
        let baseLower = base.lowercased()
        if base == "Entry" || base == "AXORCMain" || baseLower.hasSuffix("cli") {
            return true
        }
        let parent = url.deletingLastPathComponent().lastPathComponent
        let parentLower = parent.lowercased()

        // package-identity dual-entry: GUI=`AgentE2ERunnerApp`, CLI 폴더=`AgentE2ERunner`
        if let gui = packageIdentityGUIProduct(near: url), gui.hasSuffix("App") {
            let stem = String(gui.dropLast(3))
            if parent == stem || parentLower == stem.lowercased() {
                return true
            }
        }

        if let cli = cliName {
            return folderMatchesCLIName(parent: parent, parentLower: parentLower, cli: cli)
        }
        return false
    }

    /// `…/apps/<dir>/Sources/…` 에서 Packaging/package-identity.json 의 gui_product.
    static func packageIdentityGUIProduct(near url: URL) -> String? {
        var dir = url.deletingLastPathComponent()
        for _ in 0..<8 {
            let identity = dir
                .appendingPathComponent("Packaging", isDirectory: true)
                .appendingPathComponent("package-identity.json")
            if let data = try? Data(contentsOf: identity),
               let obj = ({ () -> Any? in do { return try JSONSerialization.jsonObject(with: data) } catch { return nil } }()) as? [String: Any],
               let gui = obj["gui_product"] as? String, !gui.isEmpty {
                return gui
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// interop `cli` 이름과 소스 폴더가 같은 dual-entry 인지.
    private static func folderMatchesCLIName(
        parent: String, parentLower: String, cli: String
    ) -> Bool {
        let bare = URL(fileURLWithPath: cli).lastPathComponent
        let bareLower = bare.lowercased()
        let compact = bareLower.replacingOccurrences(of: "-", with: "")
        if parent == bare || parent == cli
            || parentLower == bareLower
            || parentLower == bareLower + "-cli"
            || parentLower == bareLower + "cli"
            || parentLower == compact + "cli"
        {
            return true
        }
        let parentCompact = parentLower.replacingOccurrences(of: "-", with: "")
        let looksCLIFolder = parentLower.contains("cli")
            || parentLower.hasSuffix("ctl")
            || parent.contains("-")
            || parent == parent.lowercased()
        if looksCLIFolder, parentCompact.count >= 8, compact.count >= 8 {
            let shared = zip(parentCompact, compact).prefix(while: { $0 == $1 }).count
            if shared >= 8, abs(parentCompact.count - compact.count) <= 4 {
                return true
            }
        }
        return false
    }
}
