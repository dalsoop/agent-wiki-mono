#if os(macOS)
import AppKit
import ArchitectureCityKit
import SceneKit
import SwiftUI

public struct CitySceneView: NSViewRepresentable {
    var world: CityWorld
    var clock: Double
    var pickedId: String?
    var onPick: (String?) -> Void

    public init(world: CityWorld, clock: Double, pickedId: String?, onPick: @escaping (String?) -> Void) {
        self.world = world
        self.clock = clock
        self.pickedId = pickedId
        self.onPick = onPick
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    public func makeNSView(context: Context) -> SCNView {
        let view = CityHitView()
        view.scene = SCNScene()
        view.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.onPick = { context.coordinator.onPick($0) }

        let camera = SCNNode()
        camera.name = "city-camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 16
        camera.camera?.zFar = 400
        view.scene?.rootNode.addChildNode(camera)
        view.pointOfView = camera
        context.coordinator.camera = camera

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        view.scene?.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.eulerAngles = SCNVector3(-0.7, 0.6, 0)
        view.scene?.rootNode.addChildNode(key)
        return view
    }

    public func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.onPick = onPick
        (view as? CityHitView)?.onPick = { context.coordinator.onPick($0) }
        guard let root = view.scene?.rootNode else { return }
        let signature = world.buildings.map(\.id).sorted().joined(separator: ",")
            + "|" + world.segments.map { "\($0.from)>\($0.to)" }.sorted().joined()
            + "|" + world.labelIds.sorted().joined(separator: ",")
            + "|\(world.bounds.span)"
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            root.childNodes.filter { $0.name == "city-world" || $0.name == "city-particles" }.forEach { $0.removeFromParentNode() }
            root.addChildNode(buildWorld(world))
            let particles = SCNNode()
            particles.name = "city-particles"
            root.addChildNode(particles)
            context.coordinator.particleRoot = particles
            frameCamera(context.coordinator.camera, world: world)
        }
        updateParticles(context.coordinator.particleRoot, world: world, clock: clock)
        highlight(root: root, pickedId: pickedId)
    }

    public final class Coordinator {
        var onPick: (String?) -> Void
        var signature = ""
        var camera: SCNNode?
        var particleRoot: SCNNode?
        init(onPick: @escaping (String?) -> Void) { self.onPick = onPick }
    }

    private func frameCamera(_ camera: SCNNode?, world: CityWorld) {
        guard let camera, let cam = camera.camera else { return }
        let span = max(world.bounds.span, 10)
        cam.orthographicScale = Double(span * 0.62)
        let lift = span * 0.85
        camera.position = SCNVector3(world.bounds.centerX + lift, lift, world.bounds.centerZ + lift)
        camera.look(at: SCNVector3(world.bounds.centerX, 0, world.bounds.centerZ))
    }

    private func buildWorld(_ world: CityWorld) -> SCNNode {
        let group = SCNNode()
        group.name = "city-world"
        for district in world.districts {
            let slab = SCNBox(width: CGFloat(district.width), height: 0.08, length: CGFloat(district.depth), chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
            slab.materials = [mat]
            let node = SCNNode(geometry: slab)
            node.position = SCNVector3(district.x, -0.04, district.z)
            group.addChildNode(node)
            group.addChildNode(billboard(district.name, at: SCNVector3(district.x - district.width / 2 + 0.3, 0.08, district.z - district.depth / 2 + 0.2), color: .secondaryLabelColor))
        }
        for building in world.buildings {
            group.addChildNode(apartment(building))
            if world.labelIds.contains(building.id) || building.id == pickedId {
                group.addChildNode(billboard(building.label, at: SCNVector3(building.x, building.y + building.height / 2 + 0.2, building.z), color: .white))
            }
        }
        let byId = world.buildingById
        for segment in world.segments {
            guard let a = byId[segment.from], let b = byId[segment.to] else { continue }
            group.addChildNode(line(
                from: SCNVector3(a.x, a.y + a.height / 2 + 0.12, a.z),
                to: SCNVector3(b.x, b.y + b.height / 2 + 0.12, b.z)
            ))
        }
        return group
    }

    private func updateParticles(_ group: SCNNode?, world: CityWorld, clock: Double) {
        guard let group else { return }
        let paths = world.particlePaths
        let count = paths.isEmpty ? 0 : min(6, max(paths.count, 3))
        while group.childNodes.count < count {
            let sphere = SCNSphere(radius: 0.16)
            sphere.segmentCount = 10
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor.systemYellow
            mat.emission.contents = NSColor.systemYellow.withAlphaComponent(0.75)
            sphere.materials = [mat]
            group.addChildNode(SCNNode(geometry: sphere))
        }
        while group.childNodes.count > count { group.childNodes.last?.removeFromParentNode() }
        for i in 0..<count {
            let path = paths[i % paths.count]
            let t = Float((clock + Double(i) * 0.17).truncatingRemainder(dividingBy: 1))
            let p = CityLayout.point(along: path, t: t)
            group.childNodes[i].position = SCNVector3(p.x, p.y, p.z)
        }
    }

    private func highlight(root: SCNNode, pickedId: String?) {
        root.childNodes(passingTest: { node, _ in node.name?.hasPrefix("pick:") == true }).forEach { node in
            let id = String((node.name ?? "").dropFirst(5))
            node.scale = id == pickedId ? SCNVector3(1.18, 1.18, 1.18) : SCNVector3(1, 1, 1)
        }
    }

    private func apartment(_ building: CityBuilding) -> SCNNode {
        let color = CityPaint.color(role: building.role, usage: building.usage, face: building.face)
        let box = SCNBox(
            width: CGFloat(building.width),
            height: CGFloat(building.height),
            length: CGFloat(building.depth),
            chamferRadius: 0.03
        )
        let wall = apartmentWall(color: color, usage: building.usage)
        let roof = SCNMaterial()
        roof.diffuse.contents = color.blended(withFraction: 0.35, of: .black) ?? color
        roof.emission.contents = building.usage == .live ? color.withAlphaComponent(0.12) : NSColor.black
        box.materials = [wall, wall, wall, wall, roof, roof]
        let node = SCNNode(geometry: box)
        node.name = "pick:\(building.id)"
        node.position = SCNVector3(building.x, building.y, building.z)
        return node
    }

    private func apartmentWall(color: NSColor, usage: CityUsage) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = apartmentFacade(color: color, usage: usage)
        mat.emission.contents = usage == .live ? NSColor.systemYellow.withAlphaComponent(0.18) : NSColor.black
        mat.lightingModel = .blinn
        return mat
    }

    private func apartmentFacade(color: NSColor, usage: CityUsage) -> NSImage {
        let size = NSSize(width: 64, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let cols = 3
        let rows = 5
        let padX: CGFloat = 7
        let padY: CGFloat = 8
        let gapX: CGFloat = 4
        let gapY: CGFloat = 5
        let cellW = (size.width - padX * 2 - gapX * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = (size.height - padY * 2 - gapY * CGFloat(rows - 1)) / CGFloat(rows)
        let lit: NSColor
        switch usage {
        case .live: lit = NSColor(calibratedRed: 1, green: 0.92, blue: 0.55, alpha: 0.95)
        case .used: lit = NSColor(calibratedRed: 0.78, green: 0.88, blue: 1, alpha: 0.55)
        case .unused: lit = NSColor(calibratedWhite: 0.12, alpha: 0.85)
        }
        let dark = NSColor(calibratedWhite: 0.08, alpha: 0.9)
        for row in 0..<rows {
            for col in 0..<cols {
                let on: Bool
                switch usage {
                case .live: on = true
                case .used: on = (row + col) % 2 == 0
                case .unused: on = false
                }
                (on ? lit : dark).setFill()
                let rect = NSRect(
                    x: padX + CGFloat(col) * (cellW + gapX),
                    y: padY + CGFloat(row) * (cellH + gapY),
                    width: cellW,
                    height: cellH
                )
                NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    private func billboard(_ text: String, at position: SCNVector3, color: NSColor) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0.02)
        geo.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        geo.flatness = 0.4
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.scale = SCNVector3(0.045, 0.045, 0.045)
        node.position = position
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .Y
        node.constraints = [constraint]
        return node
    }

    private func line(from: SCNVector3, to: SCNVector3) -> SCNNode {
        let src = SCNGeometrySource(vertices: [from, to])
        let idx: [Int32] = [0, 1]
        let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.systemYellow.withAlphaComponent(0.5)
        mat.lightingModel = .constant
        geo.materials = [mat]
        return SCNNode(geometry: geo)
    }
}

final class CityHitView: SCNView {
    var onPick: ((String?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let hits = hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        var node = hits.first?.node
        while let current = node {
            if let name = current.name, name.hasPrefix("pick:") {
                onPick?(String(name.dropFirst(5)))
                return
            }
            node = current.parent
        }
        super.mouseDown(with: event)
    }
}
#endif
