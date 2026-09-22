import SwiftUI
import SceneKit

#if os(macOS)
import AppKit

/// `SceneKit` SCNView 기반 macOS 3D 구체 클러스터 렌더링 뷰입니다.
/// 마우스 궤도 회전(Orbit), 줌, 노드 피킹(클릭) 제스처를 내장 지원합니다.
public struct SphereCluster3DView: NSViewRepresentable {
    public var nodes: [SpatialNode3D]
    public var beams: [SpatialBeam3D]
    public var envelope: SpatialEnvelopeConfig?
    public var onNodeSelect: ((String) -> Void)?

    public init(
        nodes: [SpatialNode3D],
        beams: [SpatialBeam3D] = [],
        envelope: SpatialEnvelopeConfig? = nil,
        onNodeSelect: ((String) -> Void)? = nil
    ) {
        self.nodes = nodes
        self.beams = beams
        self.envelope = envelope
        self.onNodeSelect = onNodeSelect
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear

        let scene = SphereCluster3DSceneBuilder.buildScene(
            nodes: nodes,
            beams: beams,
            envelope: envelope
        )
        scnView.scene = scene

        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        scnView.addGestureRecognizer(clickRecognizer)

        return scnView
    }

    public func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.parent = self
        let scene = SphereCluster3DSceneBuilder.buildScene(
            nodes: nodes,
            beams: beams,
            envelope: envelope
        )
        nsView.scene = scene
    }

    @MainActor
    public final class Coordinator: NSObject {
        var parent: SphereCluster3DView

        init(parent: SphereCluster3DView) {
            self.parent = parent
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scnView = recognizer.view as? SCNView else { return }
            let location = recognizer.location(in: scnView)
            let hits = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            for hit in hits {
                var current: SCNNode? = hit.node
                while let node = current {
                    if let name = node.name,
                       !name.isEmpty,
                       !name.hasPrefix("__") {
                        parent.onNodeSelect?(name)
                        return
                    }
                    current = node.parent
                }
            }
        }
    }
}

#elseif os(iOS)
import UIKit

/// `SceneKit` SCNView 기반 iOS 3D 구체 클러스터 렌더링 뷰입니다.
public struct SphereCluster3DView: UIViewRepresentable {
    public var nodes: [SpatialNode3D]
    public var beams: [SpatialBeam3D]
    public var envelope: SpatialEnvelopeConfig?
    public var onNodeSelect: ((String) -> Void)?

    public init(
        nodes: [SpatialNode3D],
        beams: [SpatialBeam3D] = [],
        envelope: SpatialEnvelopeConfig? = nil,
        onNodeSelect: ((String) -> Void)? = nil
    ) {
        self.nodes = nodes
        self.beams = beams
        self.envelope = envelope
        self.onNodeSelect = onNodeSelect
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear

        let scene = SphereCluster3DSceneBuilder.buildScene(
            nodes: nodes,
            beams: beams,
            envelope: envelope
        )
        scnView.scene = scene

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        scnView.addGestureRecognizer(tapRecognizer)

        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        let scene = SphereCluster3DSceneBuilder.buildScene(
            nodes: nodes,
            beams: beams,
            envelope: envelope
        )
        uiView.scene = scene
    }

    @MainActor
    public final class Coordinator: NSObject {
        var parent: SphereCluster3DView

        init(parent: SphereCluster3DView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scnView = recognizer.view as? SCNView else { return }
            let location = recognizer.location(in: scnView)
            let hits = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            for hit in hits {
                var current: SCNNode? = hit.node
                while let node = current {
                    if let name = node.name,
                       !name.isEmpty,
                       !name.hasPrefix("__") {
                        parent.onNodeSelect?(name)
                        return
                    }
                    current = node.parent
                }
            }
        }
    }
}
#endif
