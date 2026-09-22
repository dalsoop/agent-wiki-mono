import Foundation
import RadialGraphUIKit
import Testing

@Suite struct RadialGraphUIKitTests {
    @Test func tierClassificationMatchesNormalizedRanges() {
        #expect(RadialTier.tier(for: 0.0) == .core)
        #expect(RadialTier.tier(for: 0.15) == .core)
        #expect(RadialTier.tier(for: 0.25) == .core)
        #expect(RadialTier.tier(for: 0.26) == .near)
        #expect(RadialTier.tier(for: 0.50) == .near)
        #expect(RadialTier.tier(for: 0.51) == .mid)
        #expect(RadialTier.tier(for: 0.75) == .mid)
        #expect(RadialTier.tier(for: 0.76) == .outer)
        #expect(RadialTier.tier(for: 1.0) == .outer)
        #expect(RadialTier.tier(for: 1.5) == .outer) // clamped
        #expect(RadialTier.tier(for: -0.5) == .core) // clamped
    }

    @Test func radialNodeInitializationClampsDistance() {
        let node = RadialNode(id: "test-node", label: "테스트 노드", distance: 1.25)
        #expect(node.distance == 1.0)
        #expect(node.tier == .outer)

        let centerNode = RadialNode(id: "center-node", label: "중심", distance: -0.2)
        #expect(centerNode.distance == 0.0)
        #expect(centerNode.tier == .core)
    }
}
