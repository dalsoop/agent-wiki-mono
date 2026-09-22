import Foundation

/// 파일·JSON 읽기/쓰기 안전 도우미.
public enum FileLoad {
    public static func data(contentsOf url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }

    public static func encode<T: Encodable>(_ value: T) -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(value)
        } catch {
            return nil
        }
    }

    public static func jsonObject(from data: Data) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    public static func jsonData(_ object: Any) -> Data? {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        } catch {
            return nil
        }
    }

    public static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let line = "FileLoad write failed at \(url.path): \(error.localizedDescription)\n"
            if let payload = line.data(using: .utf8) {
                FileHandle.standardError.write(payload)
            }
        }
    }

    public static func ensureDirectory(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            let line = "FileLoad directory failed at \(url.path): \(error.localizedDescription)\n"
            if let payload = line.data(using: .utf8) {
                FileHandle.standardError.write(payload)
            }
        }
    }
}
