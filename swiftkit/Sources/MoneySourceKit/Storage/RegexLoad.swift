import Foundation

public enum RegexLoad {
    public static func regularExpression(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return nil
        }
    }
}
