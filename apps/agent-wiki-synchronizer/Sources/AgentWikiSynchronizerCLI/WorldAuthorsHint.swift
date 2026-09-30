import LocalizationKit
enum WorldAuthorsHint {
    static func text(email: String, actor: String) -> String {
        if email.isEmpty {
            return CLILocalization.string("WorldAuthorsHint.return")
        }
        return email + " → " + actor + CLILocalization.string("WorldAuthorsHint.string")
    }
}
