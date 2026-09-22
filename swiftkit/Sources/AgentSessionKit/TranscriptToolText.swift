import Foundation

enum TranscriptToolText {
    /// 툴 호출을 한 줄로. 인자 전체를 뿌리면 화면이 JSON 으로 덮인다.
    static func summary(name: String, input: Any?, cap: Int) -> String {
        // codex 는 인자를 **JSON 문자열**로 싣는다 — 그대로 뿌리면 화면이 JSON 으로 덮인다.
        let decoded: Any? = jsonObject(from: input) ?? input
        guard let dict = decoded as? [String: Any] else {
            return name + (JSONLine.string(input).map { ": " + clip($0, cap) } ?? "")
        }
        // 사람이 알아볼 만한 키를 우선한다(codex 는 `cmd`, claude 는 `command`).
        for k in ["command", "cmd", "target_file", "file_path", "path", "pattern", "query", "url", "description"] {
            if let v = JSONLine.string(dict[k]) { return "\(name): \(clip(v, cap))" }
        }
        return name
    }

    /// 툴 입력에서 **파일 경로**만 뽑는다. 셸 명령줄은 파싱하지 않는다 — 인용·리다이렉션·
    /// 파이프까지 감당하려다 과대집계로 신뢰를 잃는다(`agent-session-replay` 가 같은 이유로
    /// 셸을 제외했다). 다만 apply_patch 는 헤더가 기계적이라 예외로 건진다.
    static func filePaths(_ input: Any?) -> [String] {
        let decoded: Any? = jsonObject(from: input) ?? input
        if let s = decoded as? String { return patchTargets(s) }
        guard let dict = decoded as? [String: Any] else { return [] }

        var out: [String] = []
        for k in ["file_path", "notebook_path", "path", "filePath", "target_file"] {
            if let v = JSONLine.string(dict[k]), v.hasPrefix("/") { out.append(v) }
        }
        // MultiEdit 류: edits[].file_path
        for e in (dict["edits"] as? [[String: Any]] ?? []) {
            if let v = JSONLine.string(e["file_path"]), v.hasPrefix("/") { out.append(v) }
        }
        // codex 는 patch 본문을 인자에 싣기도 한다.
        for k in ["input", "patch", "cmd", "command"] {
            if let v = JSONLine.string(dict[k]) { out += patchTargets(v) }
            if let argv = dict[k] as? [String] { out += patchTargets(argv.joined(separator: "\n")) }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// `*** Update|Add|Delete File: <경로>` 헤더에서 대상 경로.
    static func patchTargets(_ text: String) -> [String] {
        guard text.contains("*** ") else { return [] }
        var out: [String] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let l = line.trimmingCharacters(in: .whitespaces)
            for verb in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where l.hasPrefix(verb) {
                let p = String(l.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
                if !p.isEmpty { out.append(p) }
            }
        }
        return out
    }

    static func flatten(_ content: Any?, cap: Int) -> String {
        if let s = JSONLine.string(content) { return clip(s, cap) }
        if let arr = content as? [[String: Any]] {
            let joined = arr.compactMap { JSONLine.string($0["text"]) }.joined(separator: " ")
            return clip(joined, cap)
        }
        return ""
    }

    static func clip(_ s: String, _ cap: Int) -> String {
        let one = s.split(separator: "\n").first.map(String.init) ?? s
        return one.count > cap ? String(one.prefix(cap)) + "…" : one
    }

    private static func jsonObject(from input: Any?) -> [String: Any]? {
        guard let s = input as? String, let data = s.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }
}

extension TranscriptReader {
    public static func filePaths(_ input: Any?) -> [String] {
        TranscriptToolText.filePaths(input)
    }

    static func summary(name: String, input: Any?, cap: Int) -> String {
        TranscriptToolText.summary(name: name, input: input, cap: cap)
    }

    static func patchTargets(_ text: String) -> [String] {
        TranscriptToolText.patchTargets(text)
    }

    static func flatten(_ content: Any?, cap: Int) -> String {
        TranscriptToolText.flatten(content, cap: cap)
    }

    static func clip(_ s: String, _ cap: Int) -> String {
        TranscriptToolText.clip(s, cap)
    }
}
