import Foundation
import GameDepthEngineKit

public final class GameDepthCommandService {
  public let projectRoot: URL
  public let runtimeRoot: URL

  private let registry: GameDepthRegistry
  private let store: GameDepthRuntimeStore
  private let fileLock: GameDepthFileLock

  public init(projectRoot: URL, fileManager: FileManager = .default) {
    let projectRoot = projectRoot.standardizedFileURL
    let runtimeRoot = projectRoot.appendingPathComponent(".game-depth-engine", isDirectory: true)
    self.projectRoot = projectRoot
    self.runtimeRoot = runtimeRoot
    registry = GameDepthRegistry(projectRoot: projectRoot)
    store = GameDepthRuntimeStore(runtimeRoot: runtimeRoot, fileManager: fileManager)
    fileLock = GameDepthFileLock(url: runtimeRoot.appendingPathComponent("engine.lock"))
  }

  public func execute(_ request: GameDepthCommandRequest) throws -> GameDepthCommandEnvelope {
    try fileLock.withExclusiveLock {
      if let replay = try idempotentReplay(for: request) {
        try store.appendTrace(request: request, response: replay)
        return replay
      }

      let response = try evaluate(request)
      try persist(response, for: request)
      try store.appendTrace(request: request, response: response)
      return response
    }
  }

  private func evaluate(_ request: GameDepthCommandRequest) throws -> GameDepthCommandEnvelope {
    switch request.command {
    case .list:
      return .init(
        command: .list,
        dryRun: request.dryRun,
        outcome: .init(ok: true, depths: registry.scan())
      )
    case .validate:
      let scanned = registry.scan()
      let depths: [GameDepthRecord]
      if let depthID = request.arguments["depth"] {
        depths = scanned.filter { $0.manifest.id == depthID }
        guard !depths.isEmpty else {
          return .init(
            command: .validate,
            dryRun: request.dryRun,
            outcome: .init(
              ok: false,
              depths: [],
              error: .init(
                code: "GDE404_DEPTH_NOT_FOUND",
                message: "Depth '\(depthID)' was not found."
              )
            )
          )
        }
      } else {
        depths = scanned
      }
      let diagnostics = depths.flatMap(\.diagnostics)
      return .init(
        command: .validate,
        dryRun: request.dryRun,
        outcome: .init(
          ok: !diagnostics.contains { $0.severity == .error },
          depths: depths,
          diagnostics: diagnostics
        )
      )
    case .status:
      return .init(
        command: .status,
        dryRun: request.dryRun,
        outcome: .init(ok: true, state: try store.loadState())
      )
    case .pause, .speed, .step, .snapshot:
      return GameDepthCommandReducer.evaluate(request, current: try store.loadState())
    }
  }

  private func persist(
    _ response: GameDepthCommandEnvelope,
    for request: GameDepthCommandRequest
  ) throws {
    guard response.ok, !request.dryRun else { return }

    if request.command.isMutation, let state = response.state {
      try store.saveState(state)
      if request.command == .snapshot { try store.saveSnapshot(state) }
    }
    if let key = request.normalizedIdempotencyKey {
      try store.saveIdempotency(response, for: key)
    }
  }

  private func idempotentReplay(
    for request: GameDepthCommandRequest
  ) throws -> GameDepthCommandEnvelope? {
    guard !request.dryRun, let key = request.normalizedIdempotencyKey else { return nil }
    return try store.loadIdempotency()[key]?.asReplay()
  }
}

extension GameDepthCommand {
  fileprivate var isMutation: Bool {
    switch self {
    case .pause, .speed, .step, .snapshot: true
    case .list, .validate, .status: false
    }
  }
}

extension GameDepthCommandRequest {
  fileprivate var normalizedIdempotencyKey: String? {
    guard let key = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines),
      !key.isEmpty
    else { return nil }
    return key
  }
}
