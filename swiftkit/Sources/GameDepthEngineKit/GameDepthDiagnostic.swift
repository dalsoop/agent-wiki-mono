import Foundation

public struct GameDepthDiagnostic: Codable, Hashable, Sendable, CustomStringConvertible {
  public enum Code: String, Codable, Hashable, Sendable {
    case unsupportedSchema = "GDE001_UNSUPPORTED_SCHEMA"
    case malformedManifest = "GDE002_MALFORMED_MANIFEST"
    case missingScreen = "GDE003_MISSING_SCREEN"
    case missingFixture = "GDE004_MISSING_FIXTURE"
    case invalidCanvas = "GDE005_INVALID_CANVAS"
    case duplicateID = "GDE006_DUPLICATE_ID"
    case invalidScreen = "GDE007_INVALID_SCREEN"
    case unsafePath = "GDE008_UNSAFE_PATH"
  }

  public enum Severity: String, Codable, Hashable, Sendable {
    case error
    case warning
  }

  public let code: Code
  public let severity: Severity
  public let message: String
  public let depthID: String?
  public let path: String?

  public init(
    code: Code,
    severity: Severity = .error,
    message: String,
    depthID: String? = nil,
    path: String? = nil
  ) {
    self.code = code
    self.severity = severity
    self.message = message
    self.depthID = depthID
    self.path = path
  }

  public var description: String {
    let subject = depthID.map { " [\($0)]" } ?? ""
    return "\(code.rawValue)\(subject): \(message)"
  }
}
