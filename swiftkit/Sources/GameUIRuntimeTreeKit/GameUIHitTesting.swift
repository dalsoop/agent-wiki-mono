import Foundation

public struct GameUIHitResult: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        case hit
        case blocked
    }

    public var identity: GameUIIdentityPath
    public var actionID: String?
    public var disposition: Disposition
    public var interaction: GameUIInteraction?

    public init(
        identity: GameUIIdentityPath,
        actionID: String?,
        disposition: Disposition,
        interaction: GameUIInteraction?
    ) {
        self.identity = identity
        self.actionID = actionID
        self.disposition = disposition
        self.interaction = interaction
    }
}

extension GameUIRuntimeNode {
    public func hitTest(_ point: GameUIPoint) -> GameUIHitResult? {
        let localPoint = point.offsetBy(dx: -frame.x, dy: -frame.y)
        return hitTest(localPoint: localPoint, parentIdentity: .init([]))
    }

    private func hitTest(
        localPoint: GameUIPoint,
        parentIdentity: GameUIIdentityPath
    ) -> GameUIHitResult? {
        guard isVisible, opacity > 0, isEnabled else {
            return nil
        }

        let identity = parentIdentity.appending(identityToken)
        if let clipRect, !clipRect.contains(localPoint) {
            return nil
        }

        let frontToBackChildren = children.enumerated().sorted { lhs, rhs in
            if lhs.element.zIndex == rhs.element.zIndex {
                return lhs.offset > rhs.offset
            }
            return lhs.element.zIndex > rhs.element.zIndex
        }
        for (_, child) in frontToBackChildren {
            let childPoint = localPoint.offsetBy(dx: -child.frame.x, dy: -child.frame.y)
            if let hit = child.hitTest(localPoint: childPoint, parentIdentity: identity) {
                return hit
            }
        }

        let ownBounds = GameUIRect(x: 0, y: 0, width: frame.width, height: frame.height)
        guard ownBounds.contains(localPoint) else {
            return nil
        }
        if let interaction {
            return .init(
                identity: identity,
                actionID: interaction.upActionID,
                disposition: .hit,
                interaction: interaction
            )
        }
        if blocksLowerLayers {
            return .init(
                identity: identity,
                actionID: nil,
                disposition: .blocked,
                interaction: nil
            )
        }
        return nil
    }
}
