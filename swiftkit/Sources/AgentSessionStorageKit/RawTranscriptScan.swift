import Foundation

/// Claude 세션 전사본(JSONL)에서 **절단 없는** tool 결과·Bash 명령·마지막 assistant 응답을 추출한다.
///
/// `TranscriptReader` 는 UI/꼬리 미리보기를 위해 `toolTextCap`(기본 400자)으로 본문을 자르고
/// 대용량 줄의 blob 을 털어낸다(`strippingBlobs`).
/// 문서 봉인(SHA 검증)이나 인수인계 증거 수집에는 **자르지 않은 원본 본문**이 필요하므로,
/// 이 스캐너가 스트리밍으로 JSONL 을 훑어 원본을 제공한다.
/// Codex·Grok 은 전체 본문을 보장하지 않으므로 Claude 전사본 전용이다.
public enum RawTranscriptScan {
    public struct ToolUse: Sendable, Equatable {
        public var id: String
        public var name: String
        public var rawInputJSON: String

        public var input: [String: Any] {
            guard let data = rawInputJSON.data(using: .utf8) else { return [:] }
            do {
                return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } catch {
                return [:]
            }
        }

        public init(id: String, name: String, input: [String: Any] = [:]) {
            self.id = id
            self.name = name
            do {
                let data = try JSONSerialization.data(withJSONObject: input)
                self.rawInputJSON = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                self.rawInputJSON = "{}"
            }
        }

        public init(id: String, name: String, rawInputJSON: String) {
            self.id = id
            self.name = name
            self.rawInputJSON = rawInputJSON
        }

        public var filePath: String? {
            (input["file_path"] as? String) ?? (input["path"] as? String)
        }

        public var bashCommand: String? {
            input["command"] as? String
        }
    }

    public struct ToolPair: Sendable, Equatable {
        public var id: String
        public var name: String
        public var rawInputJSON: String
        public var result: String
        public var isError: Bool

        public var input: [String: Any] {
            guard let data = rawInputJSON.data(using: .utf8) else { return [:] }
            do {
                return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } catch {
                return [:]
            }
        }

        public init(
            id: String,
            name: String,
            input: [String: Any],
            result: String,
            isError: Bool = false
        ) {
            self.id = id
            self.name = name
            do {
                let data = try JSONSerialization.data(withJSONObject: input)
                self.rawInputJSON = String(data: data, encoding: .utf8) ?? "{}"
            } catch {
                self.rawInputJSON = "{}"
            }
            self.result = result
            self.isError = isError
        }

        public init(
            id: String,
            name: String,
            rawInputJSON: String,
            result: String,
            isError: Bool = false
        ) {
            self.id = id
            self.name = name
            self.rawInputJSON = rawInputJSON
            self.result = result
            self.isError = isError
        }

        public var filePath: String? {
            (input["file_path"] as? String) ?? (input["path"] as? String)
        }

        public var bashCommand: String? {
            input["command"] as? String
        }

        public var resultData: Data {
            Data(result.utf8)
        }
    }

    public struct Result: Sendable, Equatable {
        public var toolPairs: [ToolPair]
        public var lastAssistantText: String?
        public var bashCommands: [String]
        public var readPaths: [String]
        public var sessionStart: Date?
        public var parsedAny: Bool

        public init(
            toolPairs: [ToolPair] = [],
            lastAssistantText: String? = nil,
            bashCommands: [String] = [],
            readPaths: [String] = [],
            sessionStart: Date? = nil,
            parsedAny: Bool = false
        ) {
            self.toolPairs = toolPairs
            self.lastAssistantText = lastAssistantText
            self.bashCommands = bashCommands
            self.readPaths = readPaths
            self.sessionStart = sessionStart
            self.parsedAny = parsedAny
        }
    }

    @discardableResult
    public static func scan(
        path: String,
        onToolPair: ((ToolPair) -> Void)? = nil
    ) -> Result {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return Result()
        }
        defer { try? handle.close() }
        return scan(handle: handle, onToolPair: onToolPair)
    }

    @discardableResult
    public static func scan(
        url: URL,
        onToolPair: ((ToolPair) -> Void)? = nil
    ) -> Result {
        scan(path: url.path, onToolPair: onToolPair)
    }

    @discardableResult
    public static func scan(
        text: String,
        onToolPair: ((ToolPair) -> Void)? = nil
    ) -> Result {
        var scanner = StreamingScanner(onToolPair: onToolPair)
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            scanner.absorb(data)
        }
        return scanner.finalizeResult()
    }

    @discardableResult
    public static func scan(
        handle: FileHandle,
        onToolPair: ((ToolPair) -> Void)? = nil
    ) -> Result {
        var scanner = StreamingScanner(onToolPair: onToolPair)
        var carry = Data()
        while true {
            let chunk: Data
            do {
                guard let data = try handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
                chunk = data
            } catch {
                break
            }
            carry.append(chunk)
            while let nl = carry.firstIndex(of: 0x0A) {
                let line = carry.subdata(in: carry.startIndex..<nl)
                carry = carry.subdata(in: carry.index(after: nl)..<carry.endIndex)
                scanner.absorb(line)
            }
        }
        if !carry.isEmpty {
            scanner.absorb(carry)
        }
        return scanner.finalizeResult()
    }
}

extension RawTranscriptScan {
    struct StreamingScanner {
        var onToolPair: ((ToolPair) -> Void)?

        var pendingUses: [String: ToolUse] = [:]
        var toolPairs: [ToolPair] = []
        var lastAssistantText: String?
        var bashCommands: [String] = []
        var readPaths: [String] = []
        var sessionStart: Date?
        var parsedAny = false

        init(onToolPair: ((ToolPair) -> Void)?) {
            self.onToolPair = onToolPair
        }

        mutating func absorb(_ line: Data) {
            guard !line.isEmpty else { return }
            guard let obj = decodeObject(from: line) else { return }
            parsedAny = true
            ingestTimestamp(obj)
            ingestAssistantText(obj)
            ingestContentBlocks(obj)
        }

        private func decodeObject(from line: Data) -> [String: Any]? {
            do {
                return try JSONSerialization.jsonObject(with: line) as? [String: Any]
            } catch {
                return nil
            }
        }

        private mutating func ingestTimestamp(_ obj: [String: Any]) {
            guard let tsStr = obj["timestamp"] as? String,
                  let date = JSONLine.date(tsStr) else { return }
            if let cur = sessionStart {
                sessionStart = min(cur, date)
            } else {
                sessionStart = date
            }
        }

        private mutating func ingestAssistantText(_ obj: [String: Any]) {
            let msg = (obj["message"] as? [String: Any]) ?? obj
            let type = obj["type"] as? String
            let role = (obj["message"] as? [String: Any])?["role"] as? String ?? obj["role"] as? String
            guard type == "assistant" || role == "assistant" else { return }
            if let text = assistantText(in: msg), !text.isEmpty {
                lastAssistantText = text
            }
        }

        private mutating func ingestContentBlocks(_ obj: [String: Any]) {
            let msg = (obj["message"] as? [String: Any]) ?? obj
            let blocks: [[String: Any]] = {
                if let arr = msg["content"] as? [[String: Any]] { return arr }
                if let arr = obj["content"] as? [[String: Any]] { return arr }
                return []
            }()
            for blk in blocks {
                ingestBlock(blk)
            }
        }

        private mutating func ingestBlock(_ blk: [String: Any]) {
            let blkType = blk["type"] as? String
            if blkType == "tool_use" {
                handleToolUse(blk)
            } else if blkType == "tool_result" {
                handleToolResult(blk)
            }
        }

        private mutating func handleToolUse(_ blk: [String: Any]) {
            let name = blk["name"] as? String ?? ""
            let id = blk["id"] as? String ?? ""
            let input = (blk["input"] as? [String: Any]) ?? [:]
            let toolUse = ToolUse(id: id, name: name, input: input)

            if name == "Bash" || name.lowercased() == "bash",
               let cmd = toolUse.bashCommand, !cmd.isEmpty {
                bashCommands.append(cmd)
            }
            if name == "Read" || name.lowercased() == "read",
               let path = toolUse.filePath, !path.isEmpty {
                readPaths.append(path)
            }
            if !id.isEmpty {
                pendingUses[id] = toolUse
            }
        }

        private mutating func handleToolResult(_ blk: [String: Any]) {
            let toolUseId = blk["tool_use_id"] as? String ?? ""
            let isError = (blk["is_error"] as? Bool) ?? false
            let content = extractContent(blk["content"])

            guard !toolUseId.isEmpty, let use = pendingUses.removeValue(forKey: toolUseId) else {
                return
            }
            let pair = ToolPair(
                id: toolUseId,
                name: use.name,
                rawInputJSON: use.rawInputJSON,
                result: content,
                isError: isError
            )
            toolPairs.append(pair)
            onToolPair?(pair)
        }

        private func assistantText(in msg: [String: Any]) -> String? {
            if let s = msg["content"] as? String, !s.isEmpty {
                return s
            }
            if let blocks = msg["content"] as? [[String: Any]] {
                let parts = blocks.compactMap { blk -> String? in
                    guard (blk["type"] as? String) == "text" else { return nil }
                    return blk["text"] as? String
                }.filter { !$0.isEmpty }
                if !parts.isEmpty {
                    return parts.joined(separator: "\n")
                }
            }
            return nil
        }

        private func extractContent(_ content: Any?) -> String {
            if let s = content as? String {
                return s
            }
            if let arr = content as? [[String: Any]] {
                return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            if let arr = content as? [Any] {
                let texts = arr.compactMap { item -> String? in
                    if let str = item as? String { return str }
                    if let dict = item as? [String: Any] { return dict["text"] as? String }
                    return nil
                }
                return texts.joined(separator: "\n")
            }
            return ""
        }

        func finalizeResult() -> Result {
            Result(
                toolPairs: toolPairs,
                lastAssistantText: lastAssistantText,
                bashCommands: bashCommands,
                readPaths: readPaths,
                sessionStart: sessionStart,
                parsedAny: parsedAny
            )
        }
    }
}
