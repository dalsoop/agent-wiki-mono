import Foundation
import GameDepthEngineKit

public enum GameDepthCommand: String, Codable, Hashable, Sendable, CaseIterable {
  case list
  case validate
  case status
  case pause
  case speed
  case step
  case snapshot
}

public enum GameDepthSimulationSpeed: Int, Codable, Hashable, Sendable, CaseIterable {
  case stopped = 0
  case normal = 1
  case fast = 2
}

public struct GameDepthRuntimeState: Codable, Hashable, Sendable {
  public static let schemaVersion = 1

  public let schemaVersion: Int
  public var revision: Int
  public var tick: Int
  public var speed: GameDepthSimulationSpeed
  public var isPaused: Bool
  public var activeDepthID: String?

  public init(
    schemaVersion: Int = Self.schemaVersion,
    revision: Int = 0,
    tick: Int = 0,
    speed: GameDepthSimulationSpeed = .stopped,
    isPaused: Bool = true,
    activeDepthID: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.tick = tick
    self.speed = speed
    self.isPaused = isPaused
    self.activeDepthID = activeDepthID
  }
}

public struct GameDepthCommandRequest: Codable, Hashable, Sendable {
  public let command: GameDepthCommand
  public let dryRun: Bool
  public let expectedRevision: Int?
  public let idempotencyKey: String?
  public let arguments: [String: String]

  public init(
    command: GameDepthCommand,
    dryRun: Bool = false,
    expectedRevision: Int? = nil,
    idempotencyKey: String? = nil,
    arguments: [String: String] = [:]
  ) {
    self.command = command
    self.dryRun = dryRun
    self.expectedRevision = expectedRevision
    self.idempotencyKey = idempotencyKey
    self.arguments = arguments
  }
}

public struct GameDepthCommandError: Codable, Hashable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct GameDepthCommandEnvelope: Codable, Hashable, Sendable {
  public static let schemaVersion = 1

  public struct Outcome: Hashable, Sendable {
    public let ok: Bool
    public let replayed: Bool
    public let state: GameDepthRuntimeState?
    public let depths: [GameDepthRecord]?
    public let diagnostics: [GameDepthDiagnostic]
    public let error: GameDepthCommandError?

    public init(
      ok: Bool,
      replayed: Bool = false,
      state: GameDepthRuntimeState? = nil,
      depths: [GameDepthRecord]? = nil,
      diagnostics: [GameDepthDiagnostic] = [],
      error: GameDepthCommandError? = nil
    ) {
      self.ok = ok
      self.replayed = replayed
      self.state = state
      self.depths = depths
      self.diagnostics = diagnostics
      self.error = error
    }
  }

  public let schemaVersion: Int
  public let ok: Bool
  public let command: GameDepthCommand
  public let dryRun: Bool
  public let replayed: Bool
  public let state: GameDepthRuntimeState?
  public let depths: [GameDepthRecord]?
  public let diagnostics: [GameDepthDiagnostic]
  public let error: GameDepthCommandError?

  public init(
    schemaVersion: Int = Self.schemaVersion,
    command: GameDepthCommand,
    dryRun: Bool = false,
    outcome: Outcome
  ) {
    self.schemaVersion = schemaVersion
    self.ok = outcome.ok
    self.command = command
    self.dryRun = dryRun
    self.replayed = outcome.replayed
    self.state = outcome.state
    self.depths = outcome.depths
    self.diagnostics = outcome.diagnostics
    self.error = outcome.error
  }

  func asReplay() -> Self {
    Self(
      schemaVersion: schemaVersion,
      command: command,
      dryRun: dryRun,
      outcome: .init(
        ok: ok,
        replayed: true,
        state: state,
        depths: depths,
        diagnostics: diagnostics,
        error: error
      )
    )
  }
}

struct GameDepthCommandTrace: Codable, Sendable {
  let id: UUID
  let timestamp: Date
  let request: GameDepthCommandRequest
  let response: GameDepthCommandEnvelope
}
