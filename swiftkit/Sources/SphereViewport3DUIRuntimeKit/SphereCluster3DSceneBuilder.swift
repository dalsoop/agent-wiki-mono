import SwiftUI
import SceneKit
import simd

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
public typealias PlatformColor = UIColor
#endif

/// `SceneKit` 기반 3D 구체 클러스터, 빔 연결, 반투명 외피 씬을 구성하는 순수 빌더입니다.
public enum SphereCluster3DSceneBuilder {

    public static let envelopeNodeName = "__envelope__"
    public static let beamNodePrefix = "__beam_"

    /// 주어진 노드, 빔, 외피 설정을 바탕으로 SCNScene을 조립합니다.
    public static func buildScene(
        nodes: [SpatialNode3D],
        beams: [SpatialBeam3D],
        envelope: SpatialEnvelopeConfig?
    ) -> SCNScene {
        let scene = SCNScene()

        // 1. 카메라 노드 구성
        let cameraNode = SCNNode()
        cameraNode.name = "__camera__"
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 18)
        scene.rootNode.addChildNode(cameraNode)

        // 2. 조명 노드 구성 (Ambient + Omnidirectional)
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.intensity = 600
        #if os(macOS)
        ambientLightNode.light?.color = NSColor.white
        #else
        ambientLightNode.light?.color = UIColor.white
        #endif
        scene.rootNode.addChildNode(ambientLightNode)

        let omniLightNode = SCNNode()
        omniLightNode.light = SCNLight()
        omniLightNode.light?.type = .omni
        omniLightNode.light?.intensity = 1000
        omniLightNode.position = SCNVector3(10, 15, 20)
        scene.rootNode.addChildNode(omniLightNode)

        // 3. 노드 맵 구축 (ID -> Position/Radius)
        var nodePositionMap: [String: SIMD3<Float>] = [:]
        for nodeData in nodes {
            nodePositionMap[nodeData.id] = nodeData.position
            let scnNode = buildSpatialNode(nodeData)
            scene.rootNode.addChildNode(scnNode)
        }

        // 4. 빔 연결 구축
        for beamData in beams {
            if let posFrom = nodePositionMap[beamData.fromNodeId],
               let posTo = nodePositionMap[beamData.toNodeId] {
                let beamNode = buildBeamNode(beamData, from: posFrom, to: posTo)
                scene.rootNode.addChildNode(beamNode)
            }
        }

        // 5. 외피(Envelope) 구축
        if let envConfig = envelope {
            let envNode = buildEnvelopeNode(config: envConfig, nodes: nodes)
            scene.rootNode.addChildNode(envNode)
        }

        return scene
    }

    public static func buildSpatialNode(_ data: SpatialNode3D) -> SCNNode {
        let sphereGeometry = SCNSphere(radius: CGFloat(data.radius))
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor(data.color)

        if data.glowIntensity > 0 {
            material.emission.contents = PlatformColor(data.color)
            material.emission.intensity = CGFloat(data.glowIntensity)
        }

        sphereGeometry.materials = [material]

        let scnNode = SCNNode(geometry: sphereGeometry)
        scnNode.name = data.id
        scnNode.simdPosition = data.position

        if data.pulseSpeed > 0 {
            let duration = Double(max(0.1, 1.0 / data.pulseSpeed))
            let scaleUp = SCNAction.scale(to: 1.18, duration: duration / 2)
            scaleUp.timingMode = .easeInEaseOut
            let scaleDown = SCNAction.scale(to: 1.0, duration: duration / 2)
            scaleDown.timingMode = .easeInEaseOut
            let pulseAction = SCNAction.repeatForever(SCNAction.sequence([scaleUp, scaleDown]))
            scnNode.runAction(pulseAction, forKey: "pulse")
        }

        return scnNode
    }

    public static func buildBeamNode(_ beam: SpatialBeam3D, from: SIMD3<Float>, to: SIMD3<Float>) -> SCNNode {
        let delta = to - from
        let distance = simd_length(delta)

        guard distance > 0.0001 else {
            return SCNNode()
        }

        let cylinder = SCNCylinder(radius: CGFloat(beam.thickness), height: CGFloat(distance))
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor(beam.color)
        material.emission.contents = PlatformColor(beam.color)
        material.emission.intensity = 0.4
        cylinder.materials = [material]

        let beamNode = SCNNode(geometry: cylinder)
        beamNode.name = "\(beamNodePrefix)\(beam.id)"

        let mid = (from + to) * 0.5
        beamNode.simdPosition = mid

        // Y축(0, 1, 0)에서 delta 방향으로 회전 정렬
        let yAxis = SIMD3<Float>(0, 1, 0)
        let normDir = simd_normalize(delta)
        let dot = simd_dot(yAxis, normDir)

        if dot > 0.9999 {
            beamNode.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        } else if dot < -0.9999 {
            beamNode.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let cross = simd_cross(yAxis, normDir)
            let axis = simd_normalize(cross)
            let angle = acos(max(-1.0, min(1.0, dot)))
            beamNode.simdOrientation = simd_quatf(angle: angle, axis: axis)
        }

        if beam.particleFlowRate > 0 {
            let flowDuration = Double(max(0.1, 2.0 / beam.particleFlowRate))
            let dimAction = SCNAction.customAction(duration: flowDuration / 2) { node, elapsedTime in
                let progress = Float(elapsedTime / (flowDuration / 2))
                node.geometry?.firstMaterial?.emission.intensity = CGFloat(0.2 + 0.5 * (1.0 - progress))
            }
            let brightenAction = SCNAction.customAction(duration: flowDuration / 2) { node, elapsedTime in
                let progress = Float(elapsedTime / (flowDuration / 2))
                node.geometry?.firstMaterial?.emission.intensity = CGFloat(0.2 + 0.5 * progress)
            }
            let loop = SCNAction.repeatForever(SCNAction.sequence([dimAction, brightenAction]))
            beamNode.runAction(loop, forKey: "particleFlow")
        }

        return beamNode
    }

    public static func buildEnvelopeNode(config: SpatialEnvelopeConfig, nodes: [SpatialNode3D]) -> SCNNode {
        var center = SIMD3<Float>(0, 0, 0)
        var maxDistance: Float = 4.0

        if !nodes.isEmpty {
            let sum = nodes.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1.position }
            center = sum / Float(nodes.count)

            let dists = nodes.map { simd_length($0.position - center) + $0.radius }
            maxDistance = max(dists.max() ?? 4.0, 1.0)
        }

        let envelopeRadius = maxDistance * 1.25
        let sphere = SCNSphere(radius: CGFloat(envelopeRadius))
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor(config.baseColor)
        material.transparency = CGFloat(config.opacity)
        material.isDoubleSided = true
        sphere.materials = [material]

        let envNode = SCNNode(geometry: sphere)
        envNode.name = envelopeNodeName
        envNode.simdPosition = center

        if config.breathingRate > 0 {
            let duration = Double(max(0.1, 1.0 / config.breathingRate))
            let scaleFactor = CGFloat(1.0 + config.deformFactor)
            let breathIn = SCNAction.scale(to: scaleFactor, duration: duration / 2)
            breathIn.timingMode = .easeInEaseOut
            let breathOut = SCNAction.scale(to: 1.0, duration: duration / 2)
            breathOut.timingMode = .easeInEaseOut
            let loop = SCNAction.repeatForever(SCNAction.sequence([breathIn, breathOut]))
            envNode.runAction(loop, forKey: "breathing")
        }

        return envNode
    }
}
