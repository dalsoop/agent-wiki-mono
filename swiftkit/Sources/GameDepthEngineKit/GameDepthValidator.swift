import Foundation
import GameUIAssetKit

enum GameDepthValidator {
  static func validate(
    _ manifest: GameDepthManifest,
    directory: URL
  ) -> [GameDepthDiagnostic] {
    var diagnostics: [GameDepthDiagnostic] = []

    if manifest.schemaVersion != GameDepthRegistry.schemaVersion {
      diagnostics.append(
        diagnostic(
          .unsupportedSchema,
          "Expected schema version \(GameDepthRegistry.schemaVersion).",
          manifest,
          directory
        )
      )
    }

    guard isSafeRelativeFile(manifest.screen), isSafeRelativeFile(manifest.fixture) else {
      diagnostics.append(
        diagnostic(
          .unsafePath,
          "Screen and fixture paths must stay inside the depth directory.",
          manifest,
          directory
        )
      )
      return diagnostics
    }

    let screenURL = directory.appendingPathComponent(manifest.screen)
    let fixtureURL = directory.appendingPathComponent(manifest.fixture)
    if !FileManager.default.isReadableFile(atPath: fixtureURL.path) {
      diagnostics.append(
        diagnostic(.missingFixture, "Fixture file is missing.", manifest, fixtureURL))
    }
    guard FileManager.default.isReadableFile(atPath: screenURL.path) else {
      diagnostics.append(
        diagnostic(.missingScreen, "Screen manifest is missing.", manifest, screenURL))
      return diagnostics
    }

    do {
      let screen = try JSONDecoder().decode(
        GameUIScreenManifest.self,
        from: Data(contentsOf: screenURL)
      )
      if screen.canvas.width != manifest.canvas.width
        || screen.canvas.height != manifest.canvas.height
      {
        diagnostics.append(
          diagnostic(
            .invalidCanvas,
            "Screen canvas must be \(Int(manifest.canvas.width))×\(Int(manifest.canvas.height)).",
            manifest,
            screenURL
          )
        )
      }
      diagnostics += GameUIManifestValidator.validate(screen, assetRoot: directory).map { issue in
        diagnostic(
          .invalidScreen,
          "\(issue.code.rawValue): \(issue.message)",
          manifest,
          screenURL
        )
      }
    } catch {
      diagnostics.append(
        diagnostic(
          .invalidScreen,
          "screen.json could not be decoded: \(error.localizedDescription)",
          manifest,
          screenURL
        )
      )
    }
    return diagnostics
  }

  private static func diagnostic(
    _ code: GameDepthDiagnostic.Code,
    _ message: String,
    _ manifest: GameDepthManifest,
    _ url: URL
  ) -> GameDepthDiagnostic {
    GameDepthDiagnostic(code: code, message: message, depthID: manifest.id, path: url.path)
  }

  private static func isSafeRelativeFile(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else { return false }
    let parts = NSString(string: path).pathComponents
    return !parts.contains("..") && parts.count == 1
  }
}
