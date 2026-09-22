import Foundation

struct GameDepthRuntimeStore {
  let runtimeRoot: URL
  let fileManager: FileManager

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(runtimeRoot: URL, fileManager: FileManager) {
    self.runtimeRoot = runtimeRoot
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadState() throws -> GameDepthRuntimeState {
    guard fileManager.isReadableFile(atPath: stateURL.path) else { return GameDepthRuntimeState() }
    return try decoder.decode(GameDepthRuntimeState.self, from: Data(contentsOf: stateURL))
  }

  func saveState(_ state: GameDepthRuntimeState) throws {
    try write(state, to: stateURL)
  }

  func saveSnapshot(_ state: GameDepthRuntimeState) throws {
    try write(state, to: snapshotsRoot.appendingPathComponent("revision-\(state.revision).json"))
  }

  func loadIdempotency() throws -> [String: GameDepthCommandEnvelope] {
    guard fileManager.isReadableFile(atPath: idempotencyURL.path) else { return [:] }
    return try decoder.decode(
      [String: GameDepthCommandEnvelope].self, from: Data(contentsOf: idempotencyURL))
  }

  func saveIdempotency(_ response: GameDepthCommandEnvelope, for key: String) throws {
    var entries = try loadIdempotency()
    entries[key] = response
    try write(entries, to: idempotencyURL)
  }

  func appendTrace(request: GameDepthCommandRequest, response: GameDepthCommandEnvelope) throws {
    try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
    let trace = GameDepthCommandTrace(
      id: UUID(), timestamp: Date(), request: request, response: response)
    let traceEncoder = JSONEncoder()
    traceEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    traceEncoder.dateEncodingStrategy = .iso8601
    var data = try traceEncoder.encode(trace)
    data.append(0x0A)

    if !fileManager.fileExists(atPath: traceURL.path) {
      guard fileManager.createFile(atPath: traceURL.path, contents: data) else {
        throw CocoaError(.fileWriteUnknown)
      }
      return
    }
    let handle = try FileHandle(forWritingTo: traceURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  }

  private var stateURL: URL { runtimeRoot.appendingPathComponent("runtime.json") }
  private var traceURL: URL { runtimeRoot.appendingPathComponent("commands.jsonl") }
  private var idempotencyURL: URL { runtimeRoot.appendingPathComponent("idempotency.json") }
  private var snapshotsRoot: URL {
    runtimeRoot.appendingPathComponent("snapshots", isDirectory: true)
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
  }
}
