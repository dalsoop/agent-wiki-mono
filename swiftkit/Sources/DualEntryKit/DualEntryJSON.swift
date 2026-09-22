import Foundation

enum DualEntryJSON {
    static func object(from data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }
}
