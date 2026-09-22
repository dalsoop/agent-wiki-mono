import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// macOS APFS Copy-on-Write (clonefile / cp -c) 고속 복제 헬퍼.
public enum APFSCoWHelper {
    /// 대상 볼륨이 APFS이거나 Copy-on-Write(clonefile)를 지원하는지 확인.
    public static func isCoWSupported(at path: String) -> Bool {
        #if canImport(Darwin)
        var stat = statfs()
        guard statfs(path, &stat) == 0 else { return false }
        let fsName = withUnsafePointer(to: &stat.f_fstypename) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        return fsName.lowercased() == "apfs"
        #else
        return false
        #endif
    }

    /// `isCoWSupported` 별칭.
    public static func isAPFSVolume(at path: String) -> Bool {
        isCoWSupported(at: path)
    }

    private static func ensureParentDirectory(for path: String, fileManager: FileManager) throws {
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard !fileManager.fileExists(atPath: parentDir) else { return }
        try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
    }

    private static func tryDarwinClone(sourcePath: String, destinationPath: String, fileManager: FileManager) -> Bool {
        #if canImport(Darwin)
        guard !fileManager.fileExists(atPath: destinationPath) else { return false }
        return clonefile(sourcePath, destinationPath, 0) == 0
        #else
        return false
        #endif
    }

    private static func removeExistingItem(at path: String, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: path) else { return }
        try fileManager.removeItem(atPath: path)
    }

    /// 단일 파일 또는 디렉터리를 APFS Copy-on-Write로 복제.
    /// clonefile 실패 시 copyItem으로 안전하게 폴백.
    public static func cloneItem(
        at sourcePath: String,
        to destinationPath: String,
        fileManager: FileManager = .default
    ) throws {
        try ensureParentDirectory(for: destinationPath, fileManager: fileManager)
        guard !tryDarwinClone(sourcePath: sourcePath, destinationPath: destinationPath, fileManager: fileManager) else {
            return
        }
        try removeExistingItem(at: destinationPath, fileManager: fileManager)
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    /// 디렉터리 내 항목들을 지정된 제외 항목(예: `.git`)을 건너뛰고 대상 디렉터리로 CoW 복제.
    public static func cloneDirectoryContents(
        from sourceDir: String,
        to targetDir: String,
        excluding: Set<String> = [".git"],
        fileManager: FileManager = .default
    ) throws {
        if !fileManager.fileExists(atPath: targetDir) {
            try fileManager.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        }

        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: sourceDir)
        } catch {
            throw FastWorktreeError.invalidPath(sourceDir)
        }

        for entry in entries where !excluding.contains(entry) {
            let srcChild = (sourceDir as NSString).appendingPathComponent(entry)
            let dstChild = (targetDir as NSString).appendingPathComponent(entry)
            try removeExistingItem(at: dstChild, fileManager: fileManager)
            try cloneItem(at: srcChild, to: dstChild, fileManager: fileManager)
        }
    }
}
