import Darwin
import Foundation

/// 실행 중 pid 를 `.app` 번들 정체성으로 되돌리는 원자.
/// 창 목록·Dock·doctor 가 각자 `proc_pidpath` 를 복사하지 않게 한다.
public enum ProcessAppIdentity {
    public struct Identity: Equatable, Sendable {
        public var bundleId: String
        public var name: String
        public var path: String

        public init(bundleId: String, name: String, path: String) {
            self.bundleId = bundleId
            self.name = name
            self.path = path
        }
    }

    public static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func applicationRoot(fromExecutable path: String) -> String? {
        guard let range = path.range(of: ".app", options: [.backwards, .caseInsensitive]) else {
            return nil
        }
        return String(path[..<range.upperBound])
    }

    public static func infoPlist(atApp path: String) -> NSDictionary? {
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)
    }

    public static func bundleIdentifier(atApp path: String) -> String? {
        infoPlist(atApp: path)?["CFBundleIdentifier"] as? String
    }

    public static func displayName(atApp path: String) -> String {
        guard let info = infoPlist(atApp: path) else {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info[key] as? String, !name.isEmpty {
                return name
            }
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    public static func identity(pid: Int32) -> Identity? {
        guard let exe = executablePath(pid: pid),
              let root = applicationRoot(fromExecutable: exe),
              let bundleId = bundleIdentifier(atApp: root),
              !bundleId.isEmpty
        else { return nil }
        return Identity(bundleId: bundleId, name: displayName(atApp: root), path: root)
    }
}
