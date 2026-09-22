public struct GameUIAction: Equatable, Sendable {
  public let id: String
  public let payload: GameUIValue?

  public init(id: String, payload: GameUIValue? = nil) {
    self.id = id
    self.payload = payload
  }
}

public final class GameUIActionRouter {
  public typealias Handler = (GameUIAction) -> Void

  private let handler: Handler

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  @discardableResult
  public func send(
    actionID: String,
    payload: GameUIValue? = nil,
    isEnabled: Bool = true
  ) -> Bool {
    guard isEnabled else { return false }
    handler(GameUIAction(id: actionID, payload: payload))
    return true
  }
}
