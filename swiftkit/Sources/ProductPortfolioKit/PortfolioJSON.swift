import Foundation

enum PortfolioJSON {
    static func object(from data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    static func raw(from data: Data) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }
}
