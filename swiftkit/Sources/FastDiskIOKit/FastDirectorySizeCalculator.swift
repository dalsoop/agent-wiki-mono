import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FastDirectorySizeCalculator {
    /// Recursively calculates total disk space used by a directory in bytes using `stat(2)`.
    /// By default, sums `st_blocks * 512` to mirror `du` allocation behavior, or `st_size` if apparentSize is true.
    public static func calculateSize(
        at path: String,
        apparentSize: Bool = false,
        skipping: Set<String> = [".git"]
    ) -> UInt64 {
        var total: UInt64 = 0
        struct FileIdentifier: Hashable {
            let dev: UInt64
            let ino: UInt64
        }
        var visitedFiles = Set<FileIdentifier>()
        
        func traverse(dirPath: String) {
            guard let dir = opendir(dirPath) else { return }
            defer { closedir(dir) }
            
            let dirFd = dirfd(dir)
            
            while let entry = readdir(dir) {
                let name = POSIXCompat.direntName(entry)
                if name == "." || name == ".." {
                    continue
                }
                
                if skipping.contains(name) {
                    continue
                }
                
                var st = stat()
                let statRes = fstatat(dirFd, name, &st, AT_SYMLINK_NOFOLLOW)
                guard statRes == 0 else { continue }
                
                let isDir = (st.st_mode & S_IFMT) == S_IFDIR
                let fileId = FileIdentifier(dev: UInt64(st.st_dev), ino: UInt64(st.st_ino))
                
                if !visitedFiles.insert(fileId).inserted {
                    // Avoid double counting hardlinks
                    continue
                }
                
                if apparentSize {
                    total += UInt64(max(0, st.st_size))
                } else {
                    total += UInt64(max(0, st.st_blocks)) * 512
                }
                
                if isDir {
                    let subPath = (dirPath as NSString).appendingPathComponent(name)
                    traverse(dirPath: subPath)
                }
            }
        }
        
        traverse(dirPath: path)
        return total
    }
    
    /// Calculates directory size in Kilobytes (KB) mirroring `du -sk`.
    public static func calculateSizeKB(
        at path: String,
        skipping: Set<String> = [".git"]
    ) -> Int {
        let bytes = calculateSize(at: path, apparentSize: false, skipping: skipping)
        return Int((bytes + 1023) / 1024)
    }
}
