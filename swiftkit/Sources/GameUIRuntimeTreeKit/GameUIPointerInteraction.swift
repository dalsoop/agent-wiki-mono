import Foundation

public struct GameUIPointerDispatchResult: Equatable, Sendable {
    public var identity: GameUIIdentityPath?
    public var actionID: String?
    public var disposition: GameUIHitResult.Disposition?

    public init(
        identity: GameUIIdentityPath? = nil,
        actionID: String? = nil,
        disposition: GameUIHitResult.Disposition? = nil
    ) {
        self.identity = identity
        self.actionID = actionID
        self.disposition = disposition
    }
}

public struct GameUIPointerInteractionState: Equatable, Sendable {
    public private(set) var pressedIdentity: GameUIIdentityPath?
    public private(set) var hoveredIdentity: GameUIIdentityPath?
    public private(set) var capturedIdentity: GameUIIdentityPath?

    public init() {}

    @discardableResult
    public mutating func pointerDown(
        at point: GameUIPoint,
        in tree: GameUIRuntimeNode
    ) -> GameUIPointerDispatchResult {
        let hit = tree.hitTest(point)
        guard let hit, hit.disposition == .hit else {
            pressedIdentity = nil
            capturedIdentity = nil
            return dispatch(hit: hit, actionID: nil)
        }
        pressedIdentity = hit.identity
        capturedIdentity = hit.interaction?.capturesPointer == true ? hit.identity : nil
        return dispatch(hit: hit, actionID: hit.interaction?.downActionID)
    }

    @discardableResult
    public mutating func pointerMove(
        at point: GameUIPoint,
        in tree: GameUIRuntimeNode
    ) -> GameUIPointerDispatchResult {
        let hit = tree.hitTest(point)
        let nextIdentity = hit?.disposition == .hit ? hit?.identity : nil
        defer { hoveredIdentity = nextIdentity }
        guard nextIdentity != hoveredIdentity else {
            return dispatch(hit: hit, actionID: nil)
        }
        return dispatch(hit: hit, actionID: hit?.interaction?.hoverActionID)
    }

    @discardableResult
    public mutating func pointerUp(
        at point: GameUIPoint,
        in tree: GameUIRuntimeNode
    ) -> GameUIPointerDispatchResult {
        let hit = tree.hitTest(point)
        let actionID: String?
        if hit?.disposition == .hit, hit?.identity == pressedIdentity {
            actionID = hit?.interaction?.upActionID
        } else {
            actionID = nil
        }
        pressedIdentity = nil
        capturedIdentity = nil
        return dispatch(hit: hit, actionID: actionID)
    }

    private func dispatch(
        hit: GameUIHitResult?,
        actionID: String?
    ) -> GameUIPointerDispatchResult {
        .init(
            identity: hit?.identity,
            actionID: actionID,
            disposition: hit?.disposition
        )
    }
}
