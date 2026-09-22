import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// High-performance JSON decoder and encoder with mtime/size-based $O(1)$ memory caching
/// and atomic change-detected persistence integration.
public enum FastJSON: Sendable {
    private struct CacheKey: Hashable {
        let path: String
        let typeId: ObjectIdentifier
    }

    private struct CacheEntry {
        let size: Int64
        let mtimeSec: Int
        let mtimeNsec: Int
        let value: Any
    }

    private final class MemoryCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries = [CacheKey: CacheEntry]()

        func get<T>(
            path: String,
            size: Int64,
            mtimeSec: Int,
            mtimeNsec: Int,
            type: T.Type
        ) -> T? {
            lock.lock()
            defer { lock.unlock() }

            let key = CacheKey(path: path, typeId: ObjectIdentifier(type))
            guard let entry = entries[key] else { return nil }
            guard entry.size == size,
                  entry.mtimeSec == mtimeSec,
                  entry.mtimeNsec == mtimeNsec else {
                return nil
            }
            return entry.value as? T
        }

        func set<T>(
            path: String,
            size: Int64,
            mtimeSec: Int,
            mtimeNsec: Int,
            type: T.Type,
            value: T
        ) {
            lock.lock()
            defer { lock.unlock() }

            let key = CacheKey(path: path, typeId: ObjectIdentifier(type))
            entries[key] = CacheEntry(
                size: size,
                mtimeSec: mtimeSec,
                mtimeNsec: mtimeNsec,
                value: value
            )
        }

        func remove(path: String) {
            lock.lock()
            defer { lock.unlock() }

            entries = entries.filter { $0.key.path != path }
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }

            entries.removeAll(keepingCapacity: true)
        }
    }

    private static let memoryCache = MemoryCache()

    /// Clears the entire in-memory JSON decode cache.
    public static func clearCache() {
        memoryCache.clear()
    }

    /// Invalidates cached entries for a specific file path.
    public static func invalidateCache(at path: String) {
        memoryCache.remove(path: path)
    }

    /// Invalidates cached entries for a specific file URL.
    public static func invalidateCache(at url: URL) {
        memoryCache.remove(path: url.path)
    }

    /// Decodes a JSON file, checking `mtime` and `size` via stat.
    /// If both match the cached entry, returns the in-memory cached model in $O(1)$ time
    /// without reading from disk or running `JSONDecoder`.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the JSON file.
    ///   - type: Decodable target type.
    ///   - decoder: JSONDecoder instance used when cache miss occurs.
    /// - Returns: Decoded instance of `T`.
    public static func decodeCached<T: Decodable>(
        at path: String,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        var st = stat()
        guard stat(path, &st) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }

        let size = Int64(st.st_size)
        let mtimeSec = POSIXCompat.mtimeSec(st)
        let mtimeNsec = POSIXCompat.mtimeNsec(st)

        if let cached: T = memoryCache.get(
            path: path,
            size: size,
            mtimeSec: mtimeSec,
            mtimeNsec: mtimeNsec,
            type: type
        ) {
            return cached
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try decoder.decode(T.self, from: data)

        memoryCache.set(
            path: path,
            size: size,
            mtimeSec: mtimeSec,
            mtimeNsec: mtimeNsec,
            type: type,
            value: decoded
        )
        return decoded
    }

    /// Decodes a JSON URL, checking `mtime` and `size` via stat with $O(1)$ memory caching.
    public static func decodeCached<T: Decodable>(
        at url: URL,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decodeCached(at: url.path, as: type, decoder: decoder)
    }

    /// Unconditionally reads and decodes JSON from disk without consulting or updating the cache.
    public static func decode<T: Decodable>(
        at path: String,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(T.self, from: data)
    }

    /// Unconditionally reads and decodes JSON from URL without consulting or updating the cache.
    public static func decode<T: Decodable>(
        at url: URL,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decode(at: url.path, as: type, decoder: decoder)
    }

    /// Shared default JSON encoder with deterministic sorted keys.
    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Shared default JSON decoder.
    public static let defaultDecoder = JSONDecoder()

    /// Encodes an encodable value to JSON Data.
    public static func encode<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = defaultEncoder
    ) throws -> Data {
        try encoder.encode(value)
    }

    /// Encodes and writes JSON to a file atomically via `FastAtomicWriter`,
    /// skipping disk write and fsync if content is identical.
    @discardableResult
    public static func writeIfChanged<T: Encodable>(
        _ value: T,
        to path: String,
        encoder: JSONEncoder = defaultEncoder
    ) throws -> Bool {
        let data = try encoder.encode(value)
        let didWrite = try FastAtomicWriter.writeIfChanged(to: path, data: data)
        if didWrite {
            memoryCache.remove(path: path)
        }
        return didWrite
    }

    /// Encodes and writes JSON to a URL atomically via `FastAtomicWriter`,
    /// skipping disk write and fsync if content is identical.
    @discardableResult
    public static func writeIfChanged<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder = defaultEncoder
    ) throws -> Bool {
        try writeIfChanged(value, to: url.path, encoder: encoder)
    }

    /// Encodes and unconditionally writes JSON to a file atomically via `FastAtomicWriter`.
    public static func writeAtomic<T: Encodable>(
        _ value: T,
        to path: String,
        encoder: JSONEncoder = defaultEncoder
    ) throws {
        let data = try encoder.encode(value)
        try FastAtomicWriter.writeAtomic(to: path, data: data)
        memoryCache.remove(path: path)
    }

    /// Encodes and unconditionally writes JSON to a URL atomically via `FastAtomicWriter`.
    public static func writeAtomic<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder = defaultEncoder
    ) throws {
        try writeAtomic(value, to: url.path, encoder: encoder)
    }
}
