import XCTest
import SwiftUI
import SceneKit
import simd
@testable import SphereViewport3DUIRuntimeKit

final class SphereCluster3DTests: XCTestCase {

    func testSpatialNode3DProperties() {
        let node = SpatialNode3D(
            id: "node_alpha",
            position: SIMD3<Float>(1.0, 2.0, 3.0),
            radius: 1.5,
            color: .red,
            glowIntensity: 0.8,
            pulseSpeed: 1.2
        )

        XCTAssertEqual(node.id, "node_alpha")
        XCTAssertEqual(node.position, SIMD3<Float>(1.0, 2.0, 3.0))
        XCTAssertEqual(node.radius, 1.5)
        XCTAssertEqual(node.glowIntensity, 0.8)
        XCTAssertEqual(node.pulseSpeed, 1.2)
    }

    func testSpatialBeam3DProperties() {
        let beam = SpatialBeam3D(
            id: "beam_1",
            fromNodeId: "node_alpha",
            toNodeId: "node_beta",
            thickness: 0.25,
            color: .cyan,
            particleFlowRate: 2.0
        )

        XCTAssertEqual(beam.id, "beam_1")
        XCTAssertEqual(beam.fromNodeId, "node_alpha")
        XCTAssertEqual(beam.toNodeId, "node_beta")
        XCTAssertEqual(beam.thickness, 0.25)
        XCTAssertEqual(beam.particleFlowRate, 2.0)
    }

    func testSpatialEnvelopeConfigProperties() {
        let config = SpatialEnvelopeConfig(
            opacity: 0.35,
            baseColor: .purple,
            breathingRate: 0.8,
            deformFactor: 0.15
        )

        XCTAssertEqual(config.opacity, 0.35)
        XCTAssertEqual(config.breathingRate, 0.8)
        XCTAssertEqual(config.deformFactor, 0.15)
    }

    func testSceneBuilderBuildsCompleteScene() {
        let nodes = [
            SpatialNode3D(id: "node_1", position: SIMD3<Float>(0, 0, 0), radius: 1.0, color: .blue),
            SpatialNode3D(id: "node_2", position: SIMD3<Float>(3, 0, 0), radius: 1.2, color: .green),
            SpatialNode3D(id: "node_3", position: SIMD3<Float>(0, 4, 0), radius: 0.8, color: .orange)
        ]

        let beams = [
            SpatialBeam3D(id: "beam_1_2", fromNodeId: "node_1", toNodeId: "node_2", thickness: 0.1),
            SpatialBeam3D(id: "beam_1_3", fromNodeId: "node_1", toNodeId: "node_3", thickness: 0.1)
        ]

        let envelope = SpatialEnvelopeConfig(
            opacity: 0.25,
            baseColor: .white,
            breathingRate: 0.5,
            deformFactor: 0.1
        )

        let scene = SphereCluster3DSceneBuilder.buildScene(
            nodes: nodes,
            beams: beams,
            envelope: envelope
        )

        // 1. 카메라 노드 확인
        let cameraNode = scene.rootNode.childNode(withName: "__camera__", recursively: true)
        XCTAssertNotNil(cameraNode)
        XCTAssertNotNil(cameraNode?.camera)

        // 2. 노드 3개 존재 및 위치 확인
        for node in nodes {
            let scnNode = scene.rootNode.childNode(withName: node.id, recursively: true)
            XCTAssertNotNil(scnNode, "SCNNode for \(node.id) should exist")
            XCTAssertEqual(scnNode?.simdPosition.x, node.position.x)
            XCTAssertEqual(scnNode?.simdPosition.y, node.position.y)
            XCTAssertEqual(scnNode?.simdPosition.z, node.position.z)
        }

        // 3. 빔 노드 2개 존재 확인
        let beam1 = scene.rootNode.childNode(withName: "__beam_beam_1_2", recursively: true)
        let beam2 = scene.rootNode.childNode(withName: "__beam_beam_1_3", recursively: true)
        XCTAssertNotNil(beam1)
        XCTAssertNotNil(beam2)

        // 4. 외피 노드 존재 확인
        let envNode = scene.rootNode.childNode(withName: SphereCluster3DSceneBuilder.envelopeNodeName, recursively: true)
        XCTAssertNotNil(envNode)
        XCTAssertTrue(envNode?.geometry is SCNSphere)
    }

    func testBeamNodeOrientationAndDimensions() {
        let from = SIMD3<Float>(0, 0, 0)
        let to = SIMD3<Float>(0, 10, 0)
        let beam = SpatialBeam3D(id: "vertical", fromNodeId: "A", toNodeId: "B", thickness: 0.3)

        let beamNode = SphereCluster3DSceneBuilder.buildBeamNode(beam, from: from, to: to)
        XCTAssertEqual(beamNode.name, "__beam_vertical")
        guard let cylinder = beamNode.geometry as? SCNCylinder else {
            XCTFail("Geometry should be SCNCylinder")
            return
        }
        XCTAssertEqual(cylinder.height, 10.0, accuracy: 0.001)
        XCTAssertEqual(cylinder.radius, 0.3, accuracy: 0.001)
    }
}
