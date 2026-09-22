import Foundation
import FastDiskIOKit
import StateRootKit
#if os(macOS)
import Darwin
#endif

/// Vaultwarden Client GUI 잠금 상태를 읽어 CLI/에이전트가 **중복 Touch ID 를 피하게** 한다.
///
/// 배경: userKey 는 Keychain 에 있지만 앱 레벨 LAContext 게이트로 감싸 둔다. 프로세스마다
/// 메모리가 비니 CLI 한 줄마다 Touch ID 가 뜨고, GUI 가 이미 열린 상태에서도 같은 일이
/// 반복된다. GUI 가 unlocked 이고 Client 프로세스가 살아 있으면 조용히 키를 쓴다.
///
/// AppKit 격리: CLI/헤드리스 환경에서 WindowServer 연결 및 Dual-Entry Hang을 유발하는
/// NSWorkspace 대신 Darwin proc API를 직접 조회하여 앱 실행 여부를 판별한다.
public enum VaultClientSessionGate: Sendable {
    public static let keychainService = "net.ranode.vaultwarden-client"
    public static let bundleID = "net.ranode.vaultwarden-client"
    public static let stateMirrorRelativePath = ".swift-app-state/vaultwarden-client.json"

    /// Client 앱 credential-broker 소켓 (세션 이관 `op=session` 포함).
    public static func sessionBrokerSocketPath(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        homeDirectory
            .appendingPathComponent("Library/Application Support/VaultwardenClient", isDirectory: true)
            .appendingPathComponent("credential-broker.sock", isDirectory: false)
            .path
    }

    /// GUI 가 현재 잠금 해제돼 있고 앱이 떠 있으면 true — CLI 는 생체 프롬프트 없이 키 로드.
    public static func isGUIUnlocked(maxMirrorAge: TimeInterval = 6 * 3600) -> Bool {
        guard isClientAppRunning() else { return false }
        guard let snapshot = readStateMirror() else { return false }
        guard snapshot.lockState == "unlocked" else { return false }
        if let updated = snapshot.updatedAt,
           Date().timeIntervalSince(updated) > maxMirrorAge {
            return false
        }
        return true
    }

    public static func isClientAppRunning() -> Bool {
        #if os(macOS)
        let pidsCount = proc_listallpids(nil, 0)
        guard pidsCount > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(pidsCount) + 32)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard n > 0 else { continue }
            let path = String(cString: buffer)
            guard path.localizedCaseInsensitiveContains("vaultwarden") else { continue }
            guard let range = path.range(of: ".app", options: [.backwards, .caseInsensitive]) else {
                if path.hasSuffix("/VaultwardenClient") { return true }
                continue
            }
            let appRoot = String(path[..<range.upperBound])
            let plistURL = URL(fileURLWithPath: appRoot).appendingPathComponent("Contents/Info.plist")
            if let plist = NSDictionary(contentsOf: plistURL),
               let bId = plist["CFBundleIdentifier"] as? String,
               bId == bundleID {
                return true
            }
        }
        return false
        #else
        return false
        #endif
    }

    public struct MirrorSnapshot: Sendable {
        public var lockState: String
        public var updatedAt: Date?
    }

    public static func readStateMirror() -> MirrorSnapshot? {
        let path = StateRootKit.path(stateMirrorRelativePath)
        guard let data = FastFileReader.read(path) else { return nil }

        let obj: [String: Any]
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            obj = json
        } catch {
            return nil
        }

        let lock: String
        if let state = obj["state"] as? [String: Any],
           let ls = state["lockState"] as? String {
            lock = ls
        } else if let ls = obj["lockState"] as? String {
            lock = ls
        } else {
            return nil
        }

        var updated: Date?
        if let s = obj["updatedAt"] as? String {
            updated = FastDateParser.parse(s)
        }
        return MirrorSnapshot(lockState: lock, updatedAt: updated)
    }
}
