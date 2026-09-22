import Foundation

enum OrchestratorJSON {
    static func object(from data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    static func data(withJSONObject object: Any, options: JSONSerialization.WritingOptions = []) -> Data? {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: options)
        } catch {
            return nil
        }
    }
}
