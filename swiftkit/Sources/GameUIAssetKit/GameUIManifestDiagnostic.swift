public struct GameUIManifestDiagnostic: Codable, Hashable, Sendable, CustomStringConvertible {
    public enum Code: String, Codable, Hashable, Sendable {
        case unsupportedSchema = "GUI001_UNSUPPORTED_SCHEMA"
        case referenceInRuntime = "GUI002_REFERENCE_IN_RUNTIME"
        case missingComponent = "GUI003_MISSING_COMPONENT"
        case duplicateComponentHash = "GUI004_DUPLICATE_COMPONENT_HASH"
        case dynamicValueBaked = "GUI005_DYNAMIC_VALUE_BAKED"
        case missingAction = "GUI006_MISSING_ACTION"
        case missingAccessibilityLabel = "GUI007_MISSING_ACCESSIBILITY_LABEL"
        case pathEscape = "GUI008_PATH_ESCAPE"
        case outOfBounds = "GUI009_OUT_OF_BOUNDS"
    }

    public enum Severity: String, Codable, Hashable, Sendable {
        case error
        case warning
    }

    public let code: Code
    public let severity: Severity
    public let message: String
    public let subjectID: String?

    public init(
        code: Code,
        severity: Severity = .error,
        message: String,
        subjectID: String? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.subjectID = subjectID
    }

    public var description: String {
        let subject = subjectID.map { " [\($0)]" } ?? ""
        return "\(code.rawValue)\(subject): \(message)"
    }
}
