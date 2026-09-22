import Foundation

enum TestingAdapterJSON {
    static func string(from object: Any) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func object(from data: Data) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }
}
