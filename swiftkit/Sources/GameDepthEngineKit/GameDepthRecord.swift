import Foundation

public struct GameDepthRecord: Codable, Hashable, Sendable {
  public let manifest: GameDepthManifest
  public let directory: URL
  public var diagnostics: [GameDepthDiagnostic]

  public init(
    manifest: GameDepthManifest,
    directory: URL,
    diagnostics: [GameDepthDiagnostic]
  ) {
    self.manifest = manifest
    self.directory = directory
    self.diagnostics = diagnostics
  }

  public var isValid: Bool {
    !diagnostics.contains { $0.severity == .error }
  }
}
