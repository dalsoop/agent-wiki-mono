import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct FastVolumeInfo: Sendable, Equatable {
    public let path: String
    public let mountPoint: String
    public let fileSystemType: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let availableBytes: UInt64
    
    public var usedBytes: UInt64 {
        totalBytes >= freeBytes ? totalBytes - freeBytes : 0
    }
    
    public var totalKB: UInt64 { totalBytes / 1024 }
    public var availableKB: UInt64 { availableBytes / 1024 }
    public var usedKB: UInt64 { usedBytes / 1024 }
}

public enum FastVolumeStats {
    /// Queries volume statistics for a given path using Darwin `statfs(2)`.
    /// Zero subprocess spawning overhead compared to `/bin/df`.
    public static func volume(forPath path: String) -> FastVolumeInfo? {
        #if canImport(Darwin)
        var fs = statfs()
        let res = statfs(path, &fs)
        guard res == 0 else { return nil }

        let blockSize = UInt64(fs.f_bsize)
        let totalBlocks = UInt64(fs.f_blocks)
        let freeBlocks = UInt64(fs.f_bfree)
        let availBlocks = UInt64(fs.f_bavail)

        let mountPoint = withUnsafePointer(to: &fs.f_mntonname) { ptr -> String in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }

        let fsType = withUnsafePointer(to: &fs.f_fstypename) { ptr -> String in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }

        return FastVolumeInfo(
            path: path,
            mountPoint: mountPoint,
            fileSystemType: fsType,
            totalBytes: totalBlocks * blockSize,
            freeBytes: freeBlocks * blockSize,
            availableBytes: availBlocks * blockSize
        )
        #else
        var fs = statvfs()
        guard statvfs(path, &fs) == 0 else { return nil }
        let blockSize = UInt64(fs.f_frsize)
        return FastVolumeInfo(
            path: path,
            mountPoint: path,
            fileSystemType: "unknown",
            totalBytes: UInt64(fs.f_blocks) * blockSize,
            freeBytes: UInt64(fs.f_bfree) * blockSize,
            availableBytes: UInt64(fs.f_bavail) * blockSize
        )
        #endif
    }
}
