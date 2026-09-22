import Foundation

public enum FastJSONLReader {
    /// Iterates through each JSON line in a file and decodes it without multi-stage String/Substring memory allocations.
    ///
    /// - Parameters:
    ///   - path: Absolute file path.
    ///   - type: Decodable target type.
    ///   - decoder: JSONDecoder instance (reused across lines).
    ///   - handler: Callback receiving each decoded item. Return false to break early.
    public static func forEachDecodedLine<T: Decodable>(
        path: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        _ handler: (T) throws -> Bool
    ) throws {
        try FastFileReader.forEachLine(path: path) { lineBytes in
            // Skip empty or whitespace-only lines
            var start = 0
            var end = lineBytes.count
            while start < end && (lineBytes[start] == 0x20 || lineBytes[start] == 0x09 || lineBytes[start] == 0x0D || lineBytes[start] == 0x0A) {
                start += 1
            }
            while end > start && (lineBytes[end - 1] == 0x20 || lineBytes[end - 1] == 0x09 || lineBytes[end - 1] == 0x0D || lineBytes[end - 1] == 0x0A) {
                end -= 1
            }
            guard start < end else { return true }
            
            // Zero-copy subdata mapping directly into mapped buffer
            guard let base = lineBytes.baseAddress else { return true }
            let count = end - start
            let subData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start), count: count, deallocator: .none)
            do {
                let item = try decoder.decode(T.self, from: subData)
                return try handler(item)
            } catch {
                // Skip malformed individual lines in logs
                return true
            }
        }
    }
}
