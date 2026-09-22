import Foundation

public enum GameDepthCanvasPreset: String, Codable, Hashable, Sendable {
  case game1920x1080 = "game-1920x1080"

  public var width: Double { 1920 }
  public var height: Double { 1080 }
}

public struct GameDepthManifest: Codable, Hashable, Sendable {
  public struct Identity: Hashable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let displayName: String

    public init(schemaVersion: Int, id: String, displayName: String) {
      self.schemaVersion = schemaVersion
      self.id = id
      self.displayName = displayName
    }
  }

  public struct Binding: Hashable, Sendable {
    public let canvas: GameDepthCanvasPreset
    public let screen: String
    public let fixture: String
    public let shell: String
    public let entryAction: String
    public let requiredCapabilities: [String]

    public init(
      canvas: GameDepthCanvasPreset,
      screen: String,
      fixture: String,
      shell: String,
      entryAction: String,
      requiredCapabilities: [String]
    ) {
      self.canvas = canvas
      self.screen = screen
      self.fixture = fixture
      self.shell = shell
      self.entryAction = entryAction
      self.requiredCapabilities = requiredCapabilities
    }
  }

  public let schemaVersion: Int
  public let id: String
  public let displayName: String
  public let canvas: GameDepthCanvasPreset
  public let screen: String
  public let fixture: String
  public let shell: String
  public let entryAction: String
  public let requiredCapabilities: [String]

  public init(identity: Identity, binding: Binding) {
    self.schemaVersion = identity.schemaVersion
    self.id = identity.id
    self.displayName = identity.displayName
    self.canvas = binding.canvas
    self.screen = binding.screen
    self.fixture = binding.fixture
    self.shell = binding.shell
    self.entryAction = binding.entryAction
    self.requiredCapabilities = binding.requiredCapabilities
  }

  static func malformedPlaceholder(id: String) -> Self {
    Self(
      identity: .init(schemaVersion: 0, id: id, displayName: id),
      binding: .init(
        canvas: .game1920x1080,
        screen: "screen.json",
        fixture: "fixture.json",
        shell: "invalid",
        entryAction: "invalid",
        requiredCapabilities: []
      )
    )
  }
}
