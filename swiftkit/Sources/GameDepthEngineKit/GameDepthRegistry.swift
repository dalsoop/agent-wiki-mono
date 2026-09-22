import Foundation

public struct GameDepthRegistry: Sendable {
  public static let schemaVersion = 1

  public let projectRoot: URL
  public let depthsRoot: URL

  public init(projectRoot: URL, depthsDirectoryName: String = "Depths") {
    self.projectRoot = projectRoot.standardizedFileURL
    self.depthsRoot =
      projectRoot
      .appendingPathComponent(depthsDirectoryName, isDirectory: true)
      .standardizedFileURL
  }

  public func scan() -> [GameDepthRecord] {
    let manifestURLs = findManifestURLs()
    var records = manifestURLs.map(loadRecord)
    let indexesByID = Dictionary(grouping: records.indices, by: { records[$0].manifest.id })

    for (id, indexes) in indexesByID where indexes.count > 1 {
      for index in indexes {
        records[index].diagnostics.append(
          GameDepthDiagnostic(
            code: .duplicateID,
            message: "Depth ID '\(id)' is declared more than once.",
            depthID: id,
            path: records[index].directory.path
          )
        )
      }
    }

    return records.sorted {
      ($0.manifest.id, $0.directory.path) < ($1.manifest.id, $1.directory.path)
    }
  }

  private func findManifestURLs() -> [URL] {
    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    guard
      let depthDirectories = try? FileManager.default.contentsOfDirectory(
        at: depthsRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: options
      )
    else { return [] }

    return depthDirectories.compactMap { directory in
      guard
        (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      else { return nil }
      let manifestURL = directory.appendingPathComponent("depth.json", isDirectory: false)
      return FileManager.default.isReadableFile(atPath: manifestURL.path) ? manifestURL : nil
    }.sorted { $0.path < $1.path }
  }

  private func loadRecord(manifestURL: URL) -> GameDepthRecord {
    let directory = manifestURL.deletingLastPathComponent()
    let decoder = JSONDecoder()

    do {
      let manifest = try decoder.decode(GameDepthManifest.self, from: Data(contentsOf: manifestURL))
      return GameDepthRecord(
        manifest: manifest,
        directory: directory,
        diagnostics: GameDepthValidator.validate(manifest, directory: directory)
      )
    } catch {
      let id = directory.lastPathComponent
      return GameDepthRecord(
        manifest: .malformedPlaceholder(id: id),
        directory: directory,
        diagnostics: [
          GameDepthDiagnostic(
            code: .malformedManifest,
            message: "depth.json could not be decoded: \(error.localizedDescription)",
            depthID: id,
            path: manifestURL.path
          )
        ]
      )
    }
  }

}
