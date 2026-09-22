import Foundation

public enum GameUIValue: Equatable, Sendable, Codable {
  case string(String)
  case number(Double)
  case boolean(Bool)
  case array([GameUIValue])
  case object([String: GameUIValue])
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    do {
      self = .boolean(try container.decode(Bool.self))
      return
    } catch {}
    do {
      self = .number(try container.decode(Double.self))
      return
    } catch {}
    do {
      self = .string(try container.decode(String.self))
      return
    } catch {}
    do {
      self = .array(try container.decode([GameUIValue].self))
      return
    } catch {}
    self = .object(try container.decode([String: GameUIValue].self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}
