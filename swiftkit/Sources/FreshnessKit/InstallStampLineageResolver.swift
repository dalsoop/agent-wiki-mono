import Foundation

/// 스탬프 커밋 ↔ 정본(origin/main) 대조. **git 을 부르는 유일한 자리**이며,
/// CLI 시작마다 도는 코드라 세 가지를 지킨다:
///
///  1. **짧은 타임아웃** — 판정이 도구를 매달면 안 된다(도구 신선도 때문에 도구가 멈추는 건 최악).
///  2. **캐시** — 같은 커밋에 대한 답은 안 변한다. 커밋 단위로 파일 캐시(기본 30분).
///  3. **실패 시 침묵** — 저장소가 없거나 git 이 없으면 `nil`(=판정 불가)이지 경고가 아니다.
public enum InstallStampLineageResolver {
    public static func resolve(
        stamp: InstallStampFreshness.Stamp,
        cacheTTL: TimeInterval = 1800,
        now: Date = Date()
    ) -> InstallStampFreshness.Lineage? {
        guard let commit = stamp.commit, !commit.isEmpty,
              let root = stamp.sourceRoot, !root.isEmpty,
              FileManager.default.fileExists(atPath: root)
        else { return nil }

        if let cached = readCache(commit: commit, ttl: cacheTTL, now: now) { return cached }

        // 커밋이 이 저장소에 없으면(다른 클론에서 만든 바이너리) 판정하지 않는다.
        guard git(["-C", root, "cat-file", "-e", "\(commit)^{commit}"], at: root) != nil else { return nil }

        let ancestor = git(["-C", root, "merge-base", "--is-ancestor", commit, "origin/main"], at: root)
        let merged = ancestor != nil
        let behind = git(["-C", root, "rev-list", "--count", "\(commit)..origin/main"], at: root)
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let lineage = InstallStampFreshness.Lineage(mergedIntoMain: merged, behindCount: behind)
        writeCache(commit: commit, lineage: lineage, now: now)
        return lineage
    }

    // MARK: - git

    /// 성공(exit 0)이면 stdout, 아니면 nil. 2초 안에 안 끝나면 죽이고 nil.
    private static func git(_ arguments: [String], at directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = DispatchTime.now() + .seconds(2)
        let queue = DispatchQueue(label: "freshness.git.watchdog")
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        queue.asyncAfter(deadline: deadline, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 캐시

    static var cacheDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/agent-tool-freshness", isDirectory: true)
    }

    private static func cacheURL(commit: String) -> URL {
        cacheDirectory.appendingPathComponent("\(commit).json")
    }

    private static func readCache(
        commit: String, ttl: TimeInterval, now: Date
    ) -> InstallStampFreshness.Lineage? {
        let url = cacheURL(commit: commit)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let object: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            object = obj
        } catch {
            return nil
        }
        guard let stampedAt = object["at"] as? Double,
              now.timeIntervalSince1970 - stampedAt < ttl,
              let merged = object["merged"] as? Bool
        else { return nil }
        return InstallStampFreshness.Lineage(
            mergedIntoMain: merged, behindCount: object["behind"] as? Int)
    }

    private static func writeCache(
        commit: String, lineage: InstallStampFreshness.Lineage, now: Date
    ) {
        var object: [String: Any] = ["at": now.timeIntervalSince1970, "merged": lineage.mergedIntoMain]
        if let behind = lineage.behindCount { object["behind"] = behind }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            return
        }
        do { try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true) } catch { _ = error }
        do { try data.write(to: cacheURL(commit: commit), options: .atomic) } catch { _ = error }
    }
}
