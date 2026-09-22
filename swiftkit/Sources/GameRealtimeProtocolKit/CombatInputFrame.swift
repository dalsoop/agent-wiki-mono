@_exported import GameRealtimeStateKit

public enum CombatInputSource: UInt8, Codable, Sendable {
    case manual = 1
    case automatic = 2
    case remote = 3
}

public struct CombatInputButtons: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let primaryAction: Self = Self(rawValue: 1 << 0)
    public static let secondaryAction: Self = Self(rawValue: 1 << 1)
    public static let dodge: Self = Self(rawValue: 1 << 2)
    public static let interact: Self = Self(rawValue: 1 << 3)

    static let supported: Self = [
        .primaryAction,
        .secondaryAction,
        .dodge,
        .interact,
    ]
}

public struct CombatInputFrame: Hashable, Codable, Sendable {
    public let contractVersion: UInt16
    public let targetTick: UInt64
    public let controlledEntity: EntityHandle
    public let sequence: UInt64
    public let source: CombatInputSource
    public let move: FixedVector2
    public let aim: FixedVector2
    public let buttons: CombatInputButtons

    public init(
        contractVersion: UInt16 = 1,
        targetTick: UInt64,
        controlledEntity: EntityHandle,
        sequence: UInt64,
        source: CombatInputSource,
        move: FixedVector2,
        aim: FixedVector2,
        buttons: CombatInputButtons
    ) throws {
        guard contractVersion == 1 else {
            throw EngineConfigurationError.unsupportedInputContractVersion(
                contractVersion
            )
        }

        try Self.validate(move.x, component: .moveX)
        try Self.validate(move.y, component: .moveY)
        try Self.validate(aim.x, component: .aimX)
        try Self.validate(aim.y, component: .aimY)

        let unsupportedButtons = buttons.rawValue
            & ~CombatInputButtons.supported.rawValue
        guard unsupportedButtons == 0 else {
            throw EngineConfigurationError.unsupportedInputButtons(
                rawValue: buttons.rawValue
            )
        }

        self.contractVersion = contractVersion
        self.targetTick = targetTick
        self.controlledEntity = controlledEntity
        self.sequence = sequence
        self.source = source
        self.move = move
        self.aim = aim
        self.buttons = buttons
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(
                UInt16.self,
                forKey: .contractVersion
            ),
            targetTick: container.decode(UInt64.self, forKey: .targetTick),
            controlledEntity: container.decode(
                EntityHandle.self,
                forKey: .controlledEntity
            ),
            sequence: container.decode(UInt64.self, forKey: .sequence),
            source: container.decode(
                CombatInputSource.self,
                forKey: .source
            ),
            move: container.decode(FixedVector2.self, forKey: .move),
            aim: container.decode(FixedVector2.self, forKey: .aim),
            buttons: container.decode(
                CombatInputButtons.self,
                forKey: .buttons
            )
        )
    }

    private static func validate(
        _ coordinate: FixedPoint,
        component: EngineConfigurationError.InputCoordinate
    ) throws {
        guard (-FixedPoint.scale ... FixedPoint.scale).contains(
            coordinate.rawValue
        ) else {
            throw EngineConfigurationError.inputCoordinateOutOfRange(
                component: component,
                rawValue: coordinate.rawValue
            )
        }
    }
}
