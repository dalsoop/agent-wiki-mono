public enum GameUIBindingError: Error, Equatable, Sendable {
  case missingKey(String)
  case expectedObject(String)
  case expectedBoolean(String)
  case expectedNumber(String)
  case invalidMeterMaximum(String)
}

public struct GameUIMeterValue: Equatable, Sendable {
  public let current: Double
  public let maximum: Double

  public init(current: Double, maximum: Double) {
    self.current = current
    self.maximum = maximum
  }

  public var fraction: Double {
    min(max(current / maximum, 0), 1)
  }
}

public struct GameUIBindingStore: Equatable, Sendable {
  public let values: [String: GameUIValue]

  public init(values: [String: GameUIValue]) {
    self.values = values
  }

  public func value(for keyPath: String) throws -> GameUIValue {
    let keys = keyPath.split(separator: ".").map(String.init)
    guard let first = keys.first, var value = values[first] else {
      throw GameUIBindingError.missingKey(keys.first ?? keyPath)
    }

    for key in keys.dropFirst() {
      guard case .object(let object) = value else {
        throw GameUIBindingError.expectedObject(key)
      }
      guard let next = object[key] else {
        throw GameUIBindingError.missingKey(key)
      }
      value = next
    }
    return value
  }

  public func boolean(for keyPath: String) throws -> Bool {
    guard case .boolean(let value) = try value(for: keyPath) else {
      throw GameUIBindingError.expectedBoolean(keyPath)
    }
    return value
  }

  public func meterValue(for keyPath: String) throws -> GameUIMeterValue {
    guard case .object(let object) = try value(for: keyPath) else {
      throw GameUIBindingError.expectedObject(keyPath)
    }
    guard case .number(let current)? = object["current"] else {
      throw GameUIBindingError.expectedNumber("\(keyPath).current")
    }
    guard case .number(let maximum)? = object["max"] else {
      throw GameUIBindingError.expectedNumber("\(keyPath).max")
    }
    guard maximum > 0 else {
      throw GameUIBindingError.invalidMeterMaximum(keyPath)
    }
    return GameUIMeterValue(current: current, maximum: maximum)
  }
}
