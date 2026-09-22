import Foundation

public enum ProgramSlug {
    /// Deterministic, filesystem-safe install subdirectory name for a program.
    /// Always prefixed with the product id so it is unique even when the name sanitizes to empty.
    /// Keeps ASCII letters/digits, lowercased; every other run of characters becomes a single "-".
    public static func make(id: Int, name: String) -> String {
        var out = ""
        var lastDash = false
        for ch in name.lowercased() {
            let isLetterOrNumber = ch.isLetter || ch.isNumber
            let isSafeSlugChar = ch.isASCII && isLetterOrNumber
            if isSafeSlugChar {
                out.append(ch)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "\(id)" : "\(id)-\(trimmed)"
    }
}
