import Foundation
import Compression

public enum StreamCompressor {
    public enum Algorithm: Sendable {
        case lzfse, lz4, zlib
        var raw: compression_algorithm {
            switch self {
            case .lzfse: return COMPRESSION_LZFSE
            case .lz4: return COMPRESSION_LZ4
            case .zlib: return COMPRESSION_ZLIB
            }
        }
    }
    public enum CompressionError: Swift.Error { case initializationFailed, processingFailed }
    public static let bufferSize = 64 * 1024

    public static func process(
        operation: compression_stream_operation,
        algorithm: Algorithm,
        readChunk: (UnsafeMutablePointer<UInt8>, Int) throws -> Int,
        writeChunk: (UnsafePointer<UInt8>, Int) throws -> Void
    ) throws {
        let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { inBuf.deallocate(); outBuf.deallocate() }

        var stream = compression_stream(dst_ptr: outBuf, dst_size: bufferSize, src_ptr: UnsafePointer(inBuf), src_size: 0, state: nil)
        guard compression_stream_init(&stream, operation, algorithm.raw) != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.initializationFailed
        }
        defer { compression_stream_destroy(&stream) }

        while true {
            let bytesRead = try readChunk(inBuf, bufferSize)
            let flags: Int32 = (bytesRead == 0) ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            stream.src_ptr = UnsafePointer(inBuf)
            stream.src_size = bytesRead

            let finished = try processStreamLoop(
                stream: &stream,
                flags: flags,
                outBuf: outBuf,
                writeChunk: writeChunk
            )
            guard !finished else { return }
        }
    }

    private static func processStreamLoop(
        stream: inout compression_stream,
        flags: Int32,
        outBuf: UnsafeMutablePointer<UInt8>,
        writeChunk: (UnsafePointer<UInt8>, Int) throws -> Void
    ) throws -> Bool {
        while true {
            stream.dst_ptr = outBuf
            stream.dst_size = bufferSize
            let status = compression_stream_process(&stream, flags)
            guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.processingFailed }

            let produced = bufferSize - stream.dst_size
            if produced > 0 {
                try writeChunk(outBuf, produced)
            }
            guard status != COMPRESSION_STATUS_END else { return true }
            guard !(stream.dst_size > 0 && stream.src_size == 0) else { return false }
        }
    }

    public static func compress(stream: FileHandle, to: FileHandle, algorithm: Algorithm = .lzfse) throws {
        try process(
            operation: COMPRESSION_STREAM_ENCODE,
            algorithm: algorithm,
            readChunk: { ptr, count in
                let d = try stream.read(upToCount: count) ?? Data()
                d.copyBytes(to: ptr, count: d.count)
                return d.count
            },
            writeChunk: { ptr, count in
                let chunk = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr), count: count, deallocator: .none)
                try to.write(contentsOf: chunk)
            }
        )
    }

    public static func decompress(stream: FileHandle, to: FileHandle, algorithm: Algorithm = .lzfse) throws {
        try process(
            operation: COMPRESSION_STREAM_DECODE,
            algorithm: algorithm,
            readChunk: { ptr, count in
                let d = try stream.read(upToCount: count) ?? Data()
                d.copyBytes(to: ptr, count: d.count)
                return d.count
            },
            writeChunk: { ptr, count in
                let chunk = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr), count: count, deallocator: .none)
                try to.write(contentsOf: chunk)
            }
        )
    }

    public static func compress(_ data: Data, algorithm: Algorithm = .lzfse) throws -> Data {
        var res = Data()
        var off = 0
        try process(
            operation: COMPRESSION_STREAM_ENCODE,
            algorithm: algorithm,
            readChunk: { ptr, count in
                let n = min(count, data.count - off)
                guard n > 0 else { return 0 }
                data.copyBytes(to: ptr, from: off..<(off + n))
                off += n
                return n
            },
            writeChunk: { ptr, count in
                res.append(ptr, count: count)
            }
        )
        return res
    }

    public static func decompress(_ data: Data, algorithm: Algorithm = .lzfse) throws -> Data {
        var res = Data()
        var off = 0
        try process(
            operation: COMPRESSION_STREAM_DECODE,
            algorithm: algorithm,
            readChunk: { ptr, count in
                let n = min(count, data.count - off)
                guard n > 0 else { return 0 }
                data.copyBytes(to: ptr, from: off..<(off + n))
                off += n
                return n
            },
            writeChunk: { ptr, count in
                res.append(ptr, count: count)
            }
        )
        return res
    }
}
