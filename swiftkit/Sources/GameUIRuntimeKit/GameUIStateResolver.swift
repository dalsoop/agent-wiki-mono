public enum GameUIButtonState: String, Codable, Equatable, Sendable {
  case normal
  case pressed
  case disabled
}

public enum GameUIStateResolver {
  public static func buttonState(
    disabledBinding: String?,
    isPressed: Bool,
    store: GameUIBindingStore
  ) throws -> GameUIButtonState {
    if let disabledBinding, try store.boolean(for: disabledBinding) {
      return .disabled
    }
    return isPressed ? .pressed : .normal
  }
}
