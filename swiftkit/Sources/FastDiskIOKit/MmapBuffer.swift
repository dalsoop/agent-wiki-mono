import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class MmapBuffer: @unchecked Sendable {
    public let pointer: UnsafeRawPointer?
    public let size: Int
    public init(path: String, readOnly: Bool = true) throws {
        let flags = readOnly ? O_RDONLY : O_RDWR
        let fd = open(path, flags)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var st = stat()
        guard fstat(fd, &st) == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        let fileSize = Int(st.st_size)
        self.size = fileSize

        if fileSize == 0 {
            close(fd)
            self.pointer = nil
            return
        }

        let prot = PROT_READ | (readOnly ? 0 : PROT_WRITE)
        let ptr = mmap(nil, fileSize, prot, MAP_SHARED, fd, 0)
        guard ptr != MAP_FAILED, let validPtr = ptr else {
            let err = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        // POSIX guarantees mmap persists after close(fd). Close immediately to free kernel file descriptor table entries.
        close(fd)

        madvise(validPtr, fileSize, MADV_SEQUENTIAL)
        self.pointer = UnsafeRawPointer(validPtr)
    }

    public var bufferPointer: UnsafeBufferPointer<UInt8> {
        guard let pointer, size > 0 else {
            return UnsafeBufferPointer(start: nil, count: 0)
        }
        return UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: size)
    }

    public var data: Data {
        guard let pointer, size > 0 else {
            return Data()
        }
        return Data(bytes: pointer, count: size)
    }

    public var zeroCopyData: Data {
        guard let pointer, size > 0 else {
            return Data()
        }
        return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: size, deallocator: .none)
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        let rawBuf = UnsafeRawBufferPointer(start: pointer, count: size)
        return try body(rawBuf)
    }

    deinit {
        if let pointer, size > 0 {
            munmap(UnsafeMutableRawPointer(mutating: pointer), size)
        }
    }
}
