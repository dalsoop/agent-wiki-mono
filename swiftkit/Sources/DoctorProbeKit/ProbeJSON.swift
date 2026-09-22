import Foundation

enum ProbeJSON {
    static func object(from data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    static func array(from data: Data) -> [[String: Any]]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            return nil
        }
    }

    static func raw(from data: Data, options: JSONSerialization.ReadingOptions = []) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: data, options: options)
        } catch {
            return nil
        }
    }
}
