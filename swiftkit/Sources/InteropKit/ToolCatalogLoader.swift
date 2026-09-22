import Foundation

// MARK: - SearchDocument

struct SearchDocument: Sendable {
    let name: String
    let cli: String
    let version: String
    let kind: ToolKind
    let sourceID: String
    let commands: [Capabilities.Command]
    let fields: [(field: String, snippet: String, normalized: String)]
    let blob: String
    let words: Set<String>
}

// MARK: - Document Loading

extension CapabilitySearcher {
    /// 현재 인덱싱 대상인 모든 도구 엔트리 (앱, 스킬, 에이전트) 목록을 반환한다.
    public func catalogEntries() -> [ToolCatalogEntry] {
        let fm = FileManager.default
        var mtimeDate: Date?
        do {
            let attrs = try fm.attributesOfItem(atPath: store.fileURL.path)
            mtimeDate = attrs[.modificationDate] as? Date
        } catch {
            mtimeDate = nil
        }

        var docs: [SearchDocument] = []
        do {
            let loaded = try loadDocuments(currentMTime: mtimeDate)
            docs = loaded.docs
        } catch {
            return []
        }

        let summaryFields: Set<String> = ["purpose", "description", "notes", "command.summary"]
        return docs.map { doc in
            let summary = doc.fields.first(where: { summaryFields.contains($0.field) })?.snippet ?? ""
            return ToolCatalogEntry(
                name: doc.name,
                kind: doc.kind,
                sourceID: doc.sourceID,
                cli: doc.cli,
                version: doc.version,
                summary: summary,
                commands: doc.commands
            )
        }
    }

    func loadDocuments(currentMTime: Date?) throws -> (docs: [SearchDocument], appCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard !isCacheValid(currentMTime: currentMTime) else {
            return (cachedDocs, cachedAppCount)
        }

        let allDocs = try loadAllDocuments(fm: FileManager.default)
        cachedMTime = currentMTime
        cachedDocs = allDocs
        cachedAppCount = allDocs.count
        return (allDocs, allDocs.count)
    }

    private func isCacheValid(currentMTime: Date?) -> Bool {
        guard let currentMTime, let cachedMTime else { return false }
        return cachedMTime == currentMTime && !cachedDocs.isEmpty
    }

    private func loadAllDocuments(fm: FileManager) throws -> [SearchDocument] {
        var allDocs: [SearchDocument] = []
        allDocs.append(contentsOf: try loadAppDocuments(fm: fm))
        allDocs.append(contentsOf: loadAgentDocuments(fm: fm))
        allDocs.append(contentsOf: Self.loadSkills(from: skillsRoots))
        allDocs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return allDocs
    }

    private func loadAppDocuments(fm: FileManager) throws -> [SearchDocument] {
        guard fm.fileExists(atPath: store.fileURL.path) else { return [] }
        let registry = try store.load()
        return registry.apps.map { key, caps in Self.makeAppDocument(key: key, caps: caps) }
    }

    private func loadAgentDocuments(fm: FileManager) -> [SearchDocument] {
        guard let agentsURL, fm.fileExists(atPath: agentsURL.path) else { return [] }
        return Self.loadAgents(from: agentsURL)
    }

    static func makeAppDocument(key: String, caps: Capabilities) -> SearchDocument {
        var fields: [(field: String, snippet: String, normalized: String)] = []

        func add(_ field: String, _ snippet: String) {
            let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return }
            fields.append((field, s, normalize(s)))
        }

        add("name", caps.name)
        if caps.name != key { add("name", key) }
        add("cli", caps.cli)
        add("cli", (caps.cli as NSString).lastPathComponent)
        add("purpose", caps.purpose)

        for cmd in caps.commands {
            add("command.name", cmd.name)
            add("command.summary", cmd.summary)
        }
        for dep in caps.depends {
            add("depends.why", dep.why)
            add("depends.id", dep.id)
            add("depends.ref", dep.ref)
        }
        for st in caps.state {
            add("state.what", st.what)
            add("state.path", st.path)
        }

        let blob = fields.map(\.normalized).joined(separator: "\n")
        let words = Set(blob.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init))
        return SearchDocument(
            name: caps.name.isEmpty ? key : caps.name,
            cli: caps.cli,
            version: caps.version,
            kind: .app,
            sourceID: key,
            commands: caps.commands,
            fields: fields,
            blob: blob,
            words: words
        )
    }

    static func loadAgents(from url: URL) -> [SearchDocument] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return []
        }
        let payload: AgentRegistryFilePayload
        do {
            payload = try JSONDecoder().decode(AgentRegistryFilePayload.self, from: data)
        } catch {
            return []
        }
        return payload.agents.map { makeAgentDocument($0) }
    }

    static func makeAgentDocument(_ agent: AgentRegistryFilePayload.AgentEntry) -> SearchDocument {
        var fields: [(field: String, snippet: String, normalized: String)] = []

        func add(_ field: String, _ snippet: String) {
            let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return }
            fields.append((field, s, normalize(s)))
        }

        add("name", agent.name)
        add("name", agent.id)
        agent.persona.map {
            add("persona", $0)
            add("purpose", $0)
            add("command.summary", $0)
        }
        agent.notes.map {
            add("notes", $0)
            add("purpose", $0)
        }
        agent.agent.map { add("cli", $0) }
        for skill in agent.skillIDs ?? [] {
            add("skill", skill)
        }

        let blob = fields.map(\.normalized).joined(separator: "\n")
        let words = Set(blob.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init))
        return SearchDocument(
            name: agent.name,
            cli: agent.agent ?? "agent",
            version: agent.model ?? "1.0.0",
            kind: .agent,
            sourceID: agent.id,
            commands: [],
            fields: fields,
            blob: blob,
            words: words
        )
    }

    public static func parseSkillFrontmatter(content: String) -> (name: String?, description: String?) {
        SkillToolLoader.parseSkillFrontmatter(content: content)
    }

    static func makeSkillDocument(
        name: String,
        category: String?,
        version: String?,
        path: String?,
        description: String?,
        sourceID: String? = nil
    ) -> SearchDocument {
        SkillToolLoader.makeSkillDocument(
            name: name,
            category: category,
            version: version,
            path: path,
            description: description,
            sourceID: sourceID
        )
    }

    static func loadSkills(from roots: [URL]) -> [SearchDocument] {
        SkillToolLoader.loadSkills(from: roots)
    }
}

// MARK: - Skill Loading

enum SkillToolLoader {
    private static func cleanSkillDescription(_ desc: String?) -> String? {
        guard var cleaned = desc?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        let isScalarPrefix = cleaned.hasPrefix(">-") || cleaned.hasPrefix("|")
        if isScalarPrefix {
            cleaned = String(cleaned.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    static func makeSkillDocument(
        name: String,
        category: String?,
        version: String?,
        path: String?,
        description: String?,
        sourceID: String? = nil
    ) -> SearchDocument {
        var fields: [(field: String, snippet: String, normalized: String)] = []

        func add(_ field: String, _ snippet: String) {
            let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return }
            fields.append((field, s, CapabilitySearcher.normalize(s)))
        }

        add("name", name)
        category.map {
            guard !$0.isEmpty else { return }
            add("category", $0)
        }
        cleanSkillDescription(description).map {
            add("purpose", $0)
            add("description", $0)
            add("command.summary", $0)
        }

        let blob = fields.map(\.normalized).joined(separator: "\n")
        let words = Set(blob.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init))
        return SearchDocument(
            name: name,
            cli: path ?? "skill",
            version: version ?? "1.0.0",
            kind: .skill,
            sourceID: sourceID ?? name,
            commands: [],
            fields: fields,
            blob: blob,
            words: words
        )
    }

    private struct SkillFrontmatterParser {
        var name: String?
        var descriptionLines: [String] = []
        var inDescription = false

        mutating func processLine(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed != "---" else { return false }
            guard !line.hasPrefix("name:") else {
                processName(line)
                return true
            }
            guard !line.hasPrefix("description:") else {
                processDescription(line)
                return true
            }
            if inDescription {
                appendDescriptionLine(line, trimmed: trimmed)
            }
            return true
        }

        private mutating func processName(_ line: String) {
            inDescription = false
            name = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private mutating func processDescription(_ line: String) {
            inDescription = true
            let rest = line.dropFirst(12).trimmingCharacters(in: .whitespacesAndNewlines)
            let blockScalars: Set<String> = [">-", "|", ""]
            guard !blockScalars.contains(rest) else { return }
            descriptionLines.append(rest)
        }

        private mutating func appendDescriptionLine(_ line: String, trimmed: String) {
            let isIndent = line.hasPrefix("  ") || line.hasPrefix("\t")
            guard isIndent else {
                if !trimmed.isEmpty { inDescription = false }
                return
            }
            descriptionLines.append(trimmed)
        }
    }

    public static func parseSkillFrontmatter(content: String) -> (name: String?, description: String?) {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, nil)
        }
        var parser = SkillFrontmatterParser()
        for line in lines.dropFirst() {
            guard parser.processLine(line) else { break }
        }
        let desc = parser.descriptionLines.isEmpty ? nil : parser.descriptionLines.joined(separator: " ")
        return (parser.name, desc)
    }

    static func loadSkills(from roots: [URL]) -> [SearchDocument] {
        var docs: [SearchDocument] = []
        var seen = Set<String>()
        for root in roots {
            let isLock = root.lastPathComponent.hasSuffix(".json")
            if isLock {
                docs.append(contentsOf: loadSkillsFromLock(root, seen: &seen))
            } else {
                docs.append(contentsOf: loadSkillsFromDirectory(root, seen: &seen))
            }
        }
        return docs
    }

    private static func loadSkillsFromDirectory(_ root: URL, seen: inout Set<String>) -> [SearchDocument] {
        let fm = FileManager.default
        var docs: [SearchDocument] = []
        docs.append(contentsOf: loadHostSkillsRegistry(at: root, seen: &seen))

        let skillsDir = fm.fileExists(atPath: root.appendingPathComponent("skills").path)
            ? root.appendingPathComponent("skills")
            : root

        let categories = scanDirectoryEntries(at: skillsDir, fm: fm)
        for item in categories {
            docs.append(contentsOf: loadSkillsFromCategory(item, fm: fm, seen: &seen))
        }
        return docs
    }

    private static func loadSkillsFromCategory(_ item: URL, fm: FileManager, seen: inout Set<String>) -> [SearchDocument] {
        let directMD = item.appendingPathComponent("SKILL.md")
        if let doc = loadSkillMD(at: directMD, category: item.lastPathComponent, seen: &seen) {
            return [doc]
        }
        return scanDirectoryEntries(at: item, fm: fm)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { loadSkillMD(at: $0.appendingPathComponent("SKILL.md"), category: item.lastPathComponent, seen: &seen) }
    }

    private static func scanDirectoryEntries(at dirURL: URL, fm: FileManager) -> [URL] {
        var dirs: [URL] = []
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            return []
        }
        for item in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            dirs.append(item)
        }
        return dirs
    }

    private static func loadSkillMD(at fileURL: URL, category: String, seen: inout Set<String>) -> SearchDocument? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return nil
        }
        let parsed = parseSkillFrontmatter(content: content)
        let skillName = parsed.name ?? fileURL.deletingLastPathComponent().lastPathComponent
        guard seen.insert(skillName).inserted else { return nil }
        return makeSkillDocument(
            name: skillName,
            category: category,
            version: "1.0.0",
            path: fileURL.path,
            description: parsed.description,
            sourceID: "\(category)/\(skillName)"
        )
    }

    private static func loadHostSkillsRegistry(at root: URL, seen: inout Set<String>) -> [SearchDocument] {
        let fm = FileManager.default
        let manifestFile = "registry" + ".json"
        let registryURL = root.appendingPathComponent(manifestFile)
        guard fm.fileExists(atPath: registryURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: registryURL)
        } catch {
            return []
        }
        let payload: CapabilitySearcher.HostSkillsRegistryPayload
        do {
            payload = try JSONDecoder().decode(CapabilitySearcher.HostSkillsRegistryPayload.self, from: data)
        } catch {
            return []
        }
        var docs: [SearchDocument] = []
        for skill in payload.skills {
            guard seen.insert(skill.name).inserted else { continue }
            docs.append(makeSkillDocument(
                name: skill.name,
                category: skill.category,
                version: skill.version,
                path: skill.path,
                description: skill.description,
                sourceID: skill.name
            ))
        }
        return docs
    }

    private static func loadSkillsFromLock(_ lockURL: URL, seen: inout Set<String>) -> [SearchDocument] {
        let data: Data
        do {
            data = try Data(contentsOf: lockURL)
        } catch {
            return []
        }
        let payload: CapabilitySearcher.SkillLockPayload
        do {
            payload = try JSONDecoder().decode(CapabilitySearcher.SkillLockPayload.self, from: data)
        } catch {
            return []
        }
        let fm = FileManager.default
        let baseDir = lockURL.deletingLastPathComponent()
        var docs: [SearchDocument] = []
        for (name, item) in payload.skills {
            guard seen.insert(name).inserted else { continue }
            let doc = parseLockSkillEntry(name: name, item: item, baseDir: baseDir, fm: fm)
            docs.append(doc)
        }
        return docs
    }

    private static func parseLockSkillEntry(
        name: String,
        item: CapabilitySearcher.SkillLockPayload.SkillEntry,
        baseDir: URL,
        fm: FileManager
    ) -> SearchDocument {
        var desc: String?
        var skillPath = item.skillPath
        guard let relPath = item.skillPath else {
            return makeSkillDocument(name: name, category: nil, version: "1.0.0", path: nil, description: nil, sourceID: name)
        }
        let direct = baseDir.appendingPathComponent(relPath)
        guard fm.fileExists(atPath: direct.path) else {
            return makeSkillDocument(name: name, category: nil, version: "1.0.0", path: skillPath, description: nil, sourceID: name)
        }
        do {
            let content = try String(contentsOf: direct, encoding: .utf8)
            let parsed = parseSkillFrontmatter(content: content)
            desc = parsed.description
            skillPath = direct.path
        } catch {
            desc = nil
        }
        return makeSkillDocument(name: name, category: nil, version: "1.0.0", path: skillPath, description: desc, sourceID: name)
    }
}
