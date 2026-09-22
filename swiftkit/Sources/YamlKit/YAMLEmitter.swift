import Foundation

/// `YAMLNode` → YAML 텍스트. Yams `dump` 출력 형식에 맞춘다:
/// - 루트 매핑/시퀀스의 각 항목은 컨테이너 들여쓰기와 같은 열에서 시작.
/// - 매핑 값이 매핑/시퀀스면 자식은 +2 들여쓰기.
/// - 블록 시퀀스 항목(`-`)은 부모 키와 같은 들여쓰기(Yams 동작).
struct YAMLEmitter {
    private let sortKeys: Bool

    init(sortKeys: Bool) {
        self.sortKeys = sortKeys
    }

    func emit(_ node: YAMLNode) -> String {
        var out = ""
        emitNode(node, indent: 0, into: &out)
        // 끝newline은 호출처(YamlKit.dump)가 붙인다.
        return out
    }

    private func emitNode(_ node: YAMLNode, indent: Int, into out: inout String) {
        switch node {
        case .null:
            out += indentString(indent) + "null\n"
        case let .scalar(raw, plain):
            out += indentString(indent) + emitScalar(raw: raw, plain: plain) + "\n"
        case let .sequence(items):
            if items.isEmpty {
                out += indentString(indent) + "[]\n"
                return
            }
            emitSequence(items, indent: indent, into: &out)
        case let .mapping(pairs):
            if pairs.isEmpty {
                out += indentString(indent) + "{}\n"
                return
            }
            emitMapping(pairs, indent: indent, into: &out)
        }
    }

    private func emitSequence(_ items: [YAMLNode], indent: Int, into out: inout String) {
        let prefix = indentString(indent)
        for item in items {
            switch item {
            case .sequence(let nested) where !nested.isEmpty:
                // 블록 안 블록 — 항목 `-` 같은 열, 그 안 시퀀스는 같은 열(또는 +2).
                // Yams 는 시퀀스 안 시퀀스를 `- - x` 형태로 같은 들여쓰기에 내보낸다.
                out += prefix + "- "
                emitInlineSeqHeader(nested, indent: indent + 2, into: &out)
            case .mapping(let pairs) where !pairs.isEmpty:
                // 시퀀스 안 매핑 — 첫 키를 `- ` 뒤 같은 줄에.
                out += prefix + "- "
                emitMappingFirstInline(pairs, indent: indent + 2, into: &out)
            case .null:
                out += prefix + "- null\n"
            case let .scalar(raw, plain):
                out += prefix + "- " + emitScalar(raw: raw, plain: plain) + "\n"
            case .sequence:
                // 빈 시퀀스
                out += prefix + "- []\n"
            case .mapping:
                // 빈 매핑
                out += prefix + "- {}\n"
            }
        }
    }

    /// 시퀀스 안 시퀀스: `- - x` 형태로 첫 항목을 같은 줄에.
    private func emitInlineSeqHeader(_ items: [YAMLNode], indent: Int, into out: inout String) {
        // 단순화: 같은 열에 `- ` 시퀀스를 다시 내보낸다(Yams 가 이렇게 한다).
        out += "- "
        if let first = items.first {
            switch first {
            case .sequence(let nested) where !nested.isEmpty:
                emitInlineSeqHeader(nested, indent: indent + 2, into: &out)
            case .mapping(let pairs) where !pairs.isEmpty:
                emitMappingFirstInline(pairs, indent: indent, into: &out)
            case let .scalar(raw, plain):
                out += emitScalar(raw: raw, plain: plain) + "\n"
                for rest in items.dropFirst() {
                    out += indentString(indent) + "- " + scalarLine(rest) + "\n"
                }
            default:
                out += scalarLine(first) + "\n"
                for rest in items.dropFirst() {
                    out += indentString(indent) + "- " + scalarLine(rest) + "\n"
                }
            }
        } else {
            out += "\n"
        }
    }

    private func scalarLine(_ node: YAMLNode) -> String {
        switch node {
        case let .scalar(raw, plain): return emitScalar(raw: raw, plain: plain)
        case .null: return "null"
        default: return "null"
        }
    }

    /// 매핑 — 모든 키를 동일 들여쓰기로. 값이 매핑/시퀀스면 +2.
    private func emitMapping(_ pairs: [(key: YAMLNode, value: YAMLNode)], indent: Int, into out: inout String) {
        let ordered = orderedPairs(pairs)
        let prefix = indentString(indent)
        for (key, value) in ordered {
            emitKeyValuePair(key: key, value: value, prefix: prefix, indent: indent, into: &out)
        }
    }

    /// 시퀀스 항목 직후 같은 줄에 시작하는 매핑 — 첫 키는 인라인, 나머지는 들여쓰기.
    private func emitMappingFirstInline(_ pairs: [(key: YAMLNode, value: YAMLNode)], indent: Int, into out: inout String) {
        let ordered = orderedPairs(pairs)
        guard let first = ordered.first else { out += "\n"; return }
        // 첫 키-값을 인라인으로(이미 `- ` 는 출력된 상태).
        // indent 는 이 매핑의 기준 열(키가 놓이는 열). 자식 중첩은 indent+2.
        emitKeyValuePair(key: first.key, value: first.value, prefix: "", indent: indent, into: &out, inlineFirst: true)
        let prefix = indentString(indent)
        for (key, value) in ordered.dropFirst() {
            emitKeyValuePair(key: key, value: value, prefix: prefix, indent: indent, into: &out)
        }
    }

    private func emitKeyValuePair(
        key: YAMLNode,
        value: YAMLNode,
        prefix: String,
        indent: Int,
        into out: inout String,
        inlineFirst: Bool = false
    ) {
        let keyText = emitKey(key)
        switch value {
        case .null:
            out += prefix + keyText + ":\n"
        case let .scalar(raw, plain):
            out += prefix + keyText + ": " + emitScalar(raw: raw, plain: plain) + "\n"
        case .mapping(let pairs) where pairs.isEmpty:
            out += prefix + keyText + ": {}\n"
        case .sequence(let items) where items.isEmpty:
            out += prefix + keyText + ": []\n"
        case .mapping(let pairs):
            // 자식 매핑 — 같은 줄에선 안 되고 +2 들여쓰기.
            out += prefix + keyText + ":\n"
            emitMapping(pairs, indent: indent + 2, into: &out)
        case .sequence(let items):
            // 시퀀스 — 키와 같은 들여쓰기(Yams 동작).
            out += prefix + keyText + ":\n"
            emitSequence(items, indent: indent, into: &out)
        }
        _ = inlineFirst
    }

    private func orderedPairs(_ pairs: [(key: YAMLNode, value: YAMLNode)]) -> [(key: YAMLNode, value: YAMLNode)] {
        // Yams 는 `[String: Any]` dump 시 sortKeys 옵션과 무관하게 **항상 키를 정렬**해
        // 내보낸다(딕셔너리 반복 순서가 비결정적이기 때문). 이 동작을 그대로 따른다.
        // 시퀀스 항목 순서는 보존된다.
        _ = sortKeys
        return pairs.sorted { $0.key.stringKey() < $1.key.stringKey() }
    }

    private func emitKey(_ node: YAMLNode) -> String {
        switch node {
        case let .scalar(raw, _):
            return emitKeyScalar(raw)
        case .null:
            return "null"
        default:
            return ""
        }
    }

    /// 키 스칼라 — 값보다 더 보수적으로 인용(콜론·해시 등 예약 토큰 주의).
    private func emitKeyScalar(_ raw: String) -> String {
        if raw.isEmpty { return "''" }
        if needsSingleQuote(raw) { return singleQuote(raw) }
        return raw
    }

    /// 값 스칼라 직렬화. plain/따옴표 구분을 따른다.
    /// - plain(true): Bool/Int/Double 토큰 — 원문 그대로(이미 정규 토큰).
    /// - plain(false): 문자열 값 — 숫자/예약어로 보이거나 구조상 위험하면 단일따옴표.
    private func emitScalar(raw: String, plain: Bool) -> String {
        if raw.isEmpty { return "''" }
        // 여러 줄 스칼라(블록)가 들어올 수 있다 — plain 여부와 무관하게 이중따옴표로.
        if raw.contains("\n") { return doubleQuote(raw) }
        if plain {
            // 실제 숫자/불 토큰 — 그대로. 구조상 위험 문자만 단일따옴표.
            if needsSingleQuote(raw) { return singleQuote(raw) }
            return raw
        }
        // 문자열 값 — 숫자/예약어로 보이면(재파싱 시 타입이 바뀌지 않게) 단일따옴표.
        if looksLikeReservedToken(raw) || needsSingleQuote(raw) { return singleQuote(raw) }
        return raw
    }

    /// YAML 예약 토큰(null/true/false/숫자 등)과 구분하기 위해 인용이 필요한가.
    private func looksLikeReservedToken(_ s: String) -> Bool {
        switch s {
        case "null", "Null", "NULL", "~",
             "true", "True", "TRUE",
             "false", "False", "FALSE",
             ".inf", ".Inf", ".INF", "-.inf", "-.Inf", "-.INF",
             ".nan", ".NaN", ".NAN",
             "yes", "Yes", "YES", "no", "No", "NO", "on", "On", "ON", "off", "Off", "OFF":
            return true
        default:
            break
        }
        // 숫자로만 보이면 인용.
        if isNumericLooking(s) { return true }
        return false
    }

    private func isNumericLooking(_ s: String) -> Bool {
        if s.isEmpty { return false }
        // 정수/실수 토큰인지.
        let numSet = CharacterSet(charactersIn: "0123456789.+-eE")
        let allNum = s.unicodeScalars.allSatisfy { numSet.contains($0) }
        if allNum, s.contains(where: { $0.isNumber }) { return true }
        return false
    }

    /// 스칼라 값을 따옴표 없이 쓸 수 없는(구문상 위험한) 경우.
    private func needsSingleQuote(_ s: String) -> Bool {
        guard let first = s.first else { return true }
        // 선행 특수문자.
        if "-?:,&*!|>%@`\"'#,[]{}".contains(first) { return true }
        if first == " " || first == "\t" { return true }
        // 후행 공백.
        if let last = s.last, last == " " || last == "\t" { return true }
        // 콜론+공백(매핑 오인) 또는 콜론으로 끝.
        if s.contains(": ") || s.hasSuffix(":") { return true }
        // ` #`(주석 오인).
        if s.contains(" #") { return true }
        // 양끝이 단일따옴표 처리 필요 없지만, 제어문자 포함.
        if s.unicodeScalars.contains(where: { $0.value < 0x20 }) { return true }
        return false
    }

    private func singleQuote(_ s: String) -> String {
        // 단일따옴표 안의 `'`는 `''`로.
        return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func doubleQuote(_ s: String) -> String {
        var buf = "\""
        for ch in s {
            switch ch {
            case "\\": buf += "\\\\"
            case "\"": buf += "\\\""
            case "\n": buf += "\\n"
            case "\r": buf += "\\r"
            case "\t": buf += "\\t"
            default:
                if ch.asciiValue.map({ $0 < 0x20 }) == true {
                    buf += String(format: "\\x%02x", ch.asciiValue!)
                } else {
                    buf.append(ch)
                }
            }
        }
        buf += "\""
        return buf
    }

    private func indentString(_ indent: Int) -> String {
        String(repeating: " ", count: max(0, indent))
    }
}
