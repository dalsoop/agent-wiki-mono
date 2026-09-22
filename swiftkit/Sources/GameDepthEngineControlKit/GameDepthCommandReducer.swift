import Foundation

enum GameDepthCommandReducer {
  static func evaluate(
    _ request: GameDepthCommandRequest,
    current: GameDepthRuntimeState
  ) -> GameDepthCommandEnvelope {
    if let expected = request.expectedRevision, expected != current.revision {
      return failure(
        request,
        state: current,
        code: "GDE409_REVISION_CONFLICT",
        message: "Expected revision \(expected), but current revision is \(current.revision)."
      )
    }

    var proposed = current
    switch request.command {
    case .pause:
      guard let raw = request.arguments["paused"], let paused = parseBool(raw) else {
        return invalidArgument(request, state: current, message: "pause requires paused=true|false")
      }
      proposed.isPaused = paused
      if !paused, proposed.speed == .stopped { proposed.speed = .normal }
    case .speed:
      guard
        let raw = request.arguments["value"],
        let value = Int(raw),
        let speed = GameDepthSimulationSpeed(rawValue: value)
      else {
        return invalidArgument(request, state: current, message: "speed requires value=0|1|2")
      }
      proposed.speed = speed
      proposed.isPaused = speed == .stopped
    case .step:
      guard
        let raw = request.arguments["hours"],
        let hours = Int(raw),
        (1...168).contains(hours)
      else {
        return invalidArgument(request, state: current, message: "step requires hours=1...168")
      }
      proposed.tick += hours
    case .snapshot:
      break
    case .list, .validate, .status:
      return invalidArgument(request, state: current, message: "command is not mutable")
    }

    proposed.revision += 1
    return .init(
      command: request.command,
      dryRun: request.dryRun,
      outcome: .init(ok: true, state: proposed)
    )
  }

  private static func invalidArgument(
    _ request: GameDepthCommandRequest,
    state: GameDepthRuntimeState,
    message: String
  ) -> GameDepthCommandEnvelope {
    failure(request, state: state, code: "GDE400_INVALID_ARGUMENT", message: message)
  }

  private static func failure(
    _ request: GameDepthCommandRequest,
    state: GameDepthRuntimeState,
    code: String,
    message: String
  ) -> GameDepthCommandEnvelope {
    .init(
      command: request.command,
      dryRun: request.dryRun,
      outcome: .init(
        ok: false,
        state: state,
        error: .init(code: code, message: message)
      )
    )
  }

  private static func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1", "yes", "on": true
    case "false", "0", "no", "off": false
    default: nil
    }
  }
}
