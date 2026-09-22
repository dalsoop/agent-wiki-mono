import Foundation

/// 설치본이 Dock 아이콘을 숨길 수 있는지. 정책 JSON과 섞지 않는다.
public enum FleetDeskHideBuild: Sendable {
    public static let hookSymbol = "FleetDeskShouldForceAccessory"
    /// C 생성자가 링크됐는지. Swift 심볼만 있으면 훅이 안 돈다.
    public static let ctorSymbol = "fleet_desk_ctor"

    public static func canHideDockIcon(
        bundlePath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = URL(fileURLWithPath: bundlePath, isDirectory: true)
        let info = root.appendingPathComponent("Contents/Info.plist")
        if let plist = NSDictionary(contentsOf: info),
           FleetDeskPolicy.isTruthyLSUIElement(plist["LSUIElement"])
        {
            return true
        }
        let macOS = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: macOS.path) else {
            return false
        }
        let needles = [Data(hookSymbol.utf8), Data(ctorSymbol.utf8)]
        for name in names {
            let exec = macOS.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: exec.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            guard let data = try? Data(contentsOf: exec, options: [.mappedIfSafe]) else { continue }
            if needles.contains(where: { data.range(of: $0) != nil }) { return true }
        }
        return false
    }
}
