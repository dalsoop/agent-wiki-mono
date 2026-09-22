import Foundation

enum MiniDiffDumper {
    static func escapeString(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count + 2)
        for char in string {
            switch char {
            case "\\": result.append("\\\\")
            case "\"": result.append("\\\"")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            default: result.append(char)
            }
        }
        return result
    }

    static func dumpAny(_ value: Any?, depth: Int, maxDepth: Int) -> String {
        guard depth <= maxDepth else { return "..." }
        guard let value = value else { return "nil" }

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle != .optional else {
            return dumpOptional(mirror, depth: depth, maxDepth: maxDepth)
        }

        if let primitive = dumpPrimitive(value) {
            return primitive
        }

        return dumpComposite(value: value, mirror: mirror, depth: depth, maxDepth: maxDepth)
    }

    private static func dumpOptional(_ mirror: Mirror, depth: Int, maxDepth: Int) -> String {
        guard let first = mirror.children.first else { return "nil" }
        return dumpAny(first.value, depth: depth, maxDepth: maxDepth)
    }

    private static func dumpPrimitive(_ value: Any) -> String? {
        switch value {
        case let str as String: return "\"\(escapeString(str))\""
        case let chr as Character: return "\"\(escapeString(String(chr)))\""
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return "\(i)"
        case let i as Int8: return "\(i)"
        case let i as Int16: return "\(i)"
        case let i as Int32: return "\(i)"
        case let i as Int64: return "\(i)"
        case let u as UInt: return "\(u)"
        case let u as UInt8: return "\(u)"
        case let u as UInt16: return "\(u)"
        case let u as UInt32: return "\(u)"
        case let u as UInt64: return "\(u)"
        case let d as Double: return "\(d)"
        case let f as Float: return "\(f)"
        case let url as URL: return "URL(\"\(url.absoluteString)\")"
        case let uuid as UUID: return "UUID(\"\(uuid.uuidString)\")"
        case let dt as Date: return "Date(\"\(dt.description)\")"
        default: return nil
        }
    }

    private static func dumpComposite(value: Any, mirror: Mirror, depth: Int, maxDepth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = String(repeating: "  ", count: depth + 1)

        switch mirror.displayStyle {
        case .collection:
            return dumpCollection(mirror: mirror, depth: depth, maxDepth: maxDepth, indent: indent, childIndent: childIndent)
        case .set:
            return dumpSet(mirror: mirror, depth: depth, maxDepth: maxDepth, indent: indent, childIndent: childIndent)
        case .dictionary:
            return dumpDictionary(mirror: mirror, depth: depth, maxDepth: maxDepth, indent: indent, childIndent: childIndent)
        case .struct, .class:
            return dumpStructOrClass(mirror: mirror, depth: depth, maxDepth: maxDepth, indent: indent, childIndent: childIndent)
        case .enum:
            return dumpEnum(value: value, mirror: mirror, depth: depth, maxDepth: maxDepth)
        case .tuple:
            return dumpTuple(mirror: mirror, depth: depth, maxDepth: maxDepth, indent: indent, childIndent: childIndent)
        case .optional:
            return dumpOptional(mirror, depth: depth, maxDepth: maxDepth)
        case .none, .some:
            return "\(value)"
        @unknown default:
            return "\(value)"
        }
    }

    private static func dumpCollection(mirror: Mirror, depth: Int, maxDepth: Int, indent: String, childIndent: String) -> String {
        let children = Array(mirror.children)
        guard !children.isEmpty else { return "[]" }
        var lines = ["["]
        for child in children {
            lines.append("\(childIndent)\(dumpAny(child.value, depth: depth + 1, maxDepth: maxDepth)),")
        }
        lines.append("\(indent)]")
        return lines.joined(separator: "\n")
    }

    private static func dumpSet(mirror: Mirror, depth: Int, maxDepth: Int, indent: String, childIndent: String) -> String {
        let children = Array(mirror.children)
        guard !children.isEmpty else { return "[]" }
        let elements = children.map { dumpAny($0.value, depth: depth + 1, maxDepth: maxDepth) }.sorted()
        var lines = ["["]
        for elem in elements {
            lines.append("\(childIndent)\(elem),")
        }
        lines.append("\(indent)]")
        return lines.joined(separator: "\n")
    }

    private static func dumpDictionary(mirror: Mirror, depth: Int, maxDepth: Int, indent: String, childIndent: String) -> String {
        let children = Array(mirror.children)
        guard !children.isEmpty else { return "[:]" }
        var entries: [(keyStr: String, line: String)] = []
        for child in children {
            let pairMirror = Mirror(reflecting: child.value)
            let pair = extractKeyValue(pairMirror)
            guard let key = pair.key, let val = pair.val else { continue }
            let kDump = dumpAny(key, depth: 0, maxDepth: maxDepth)
            let vDump = dumpAny(val, depth: depth + 1, maxDepth: maxDepth)
            entries.append((keyStr: kDump, line: "\(childIndent)\(kDump): \(vDump),"))
        }
        entries.sort { $0.keyStr < $1.keyStr }
        var lines = ["["]
        for entry in entries {
            lines.append(entry.line)
        }
        lines.append("\(indent)]")
        return lines.joined(separator: "\n")
    }

    private static func extractKeyValue(_ pairMirror: Mirror) -> (key: Any?, val: Any?) {
        var key: Any?
        var val: Any?
        for pairChild in pairMirror.children {
            switch pairChild.label {
            case "key": key = pairChild.value
            case "value": val = pairChild.value
            default: break
            }
        }
        return (key, val)
    }

    private static func dumpStructOrClass(mirror: Mirror, depth: Int, maxDepth: Int, indent: String, childIndent: String) -> String {
        var allChildren: [(label: String?, value: Any)] = []
        var current: Mirror? = mirror
        while let m = current {
            allChildren.append(contentsOf: m.children)
            current = m.superclassMirror
        }
        let typeName = "\(mirror.subjectType)"
        guard !allChildren.isEmpty else { return "\(typeName)()" }

        var lines = ["\(typeName)("]
        for (idx, child) in allChildren.enumerated() {
            let label = child.label ?? "_\(idx)"
            let childDump = dumpAny(child.value, depth: depth + 1, maxDepth: maxDepth)
            lines.append("\(childIndent)\(label): \(childDump),")
        }
        lines.append("\(indent))")
        return lines.joined(separator: "\n")
    }

    private static func dumpEnum(value: Any, mirror: Mirror, depth: Int, maxDepth: Int) -> String {
        let children = Array(mirror.children)
        guard let child = children.first else { return ".\(value)" }
        let caseName = child.label ?? "\(value)"
        let payloadMirror = Mirror(reflecting: child.value)
        guard payloadMirror.displayStyle == .tuple else {
            let pDump = dumpAny(child.value, depth: depth + 1, maxDepth: maxDepth)
            return ".\(caseName)(\(pDump))"
        }
        var payloadItems: [String] = []
        for pChild in payloadMirror.children {
            let pDump = dumpAny(pChild.value, depth: depth + 1, maxDepth: maxDepth)
            let formatted = formatPayloadLabel(pChild.label, dump: pDump)
            payloadItems.append(formatted)
        }
        return ".\(caseName)(\(payloadItems.joined(separator: ", ")))"
    }

    private static func formatPayloadLabel(_ label: String?, dump: String) -> String {
        guard let label = label, !label.hasPrefix(".") else { return dump }
        return "\(label): \(dump)"
    }

    private static func dumpTuple(mirror: Mirror, depth: Int, maxDepth: Int, indent: String, childIndent: String) -> String {
        let children = Array(mirror.children)
        guard !children.isEmpty else { return "()" }
        var lines = ["("]
        for child in children {
            let childDump = dumpAny(child.value, depth: depth + 1, maxDepth: maxDepth)
            let formatted = formatPayloadLabel(child.label, dump: childDump)
            lines.append("\(childIndent)\(formatted),")
        }
        lines.append("\(indent))")
        return lines.joined(separator: "\n")
    }
}
