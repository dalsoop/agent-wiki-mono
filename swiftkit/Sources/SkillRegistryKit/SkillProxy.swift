import Foundation

/// 스킬의 해석 계층 (해석 출처)
public enum SkillResolutionLayer: String, Sendable, Codable, Equatable {
    /// 룸 로컬 격리 영역 (`room/skills/<name>`)
    case roomLocal = "room_local"
    /// 테넌트 격리 영역 (`~/.tenants/<tenant>/skills/<name>` 등)
    case tenant = "tenant"
    /// 전역 도구 스킬 (`~/.claude/skills`, `~/.codex/skills`, ...)
    case global = "global"
}

/// 계층형 단방향 프록시를 통해 해석된 스킬 정보
public struct ResolvedSkill: Sendable, Codable, Equatable, Identifiable {
    public var ref: SkillRef
    public var layer: SkillResolutionLayer

    public var id: String { ref.id }
    public var name: String { ref.name }
    public var path: String { ref.path }
    public var tool: String { ref.tool }
    public var scope: String { ref.scope }

    public init(ref: SkillRef, layer: SkillResolutionLayer) {
        self.ref = ref
        self.layer = layer
    }
}

/// 단방향 스킬 캐스케이드 프록시
///
/// 스킬 탐색 시 단방향 상속 계층을 준수한다:
/// 1. Room Local (`roomURL/skills`) — 1순위 (최상위 우선순위)
/// 2. Tenant (`tenantSkillsURL`) — 2순위
/// 3. Global (`SkillRegistry`) — 3순위 (기본값)
///
/// 상위 계층의 스킬을 수정하려면 Copy-on-Write (`materialize`)를 통해
/// 하위 룸 로컬 영역으로 안전 복제한 후 수정한다.
public struct SkillProxy: Sendable {
    public let roomSkillsURL: URL?
    public let tenantSkillsURL: URL?
    public let globalRegistry: SkillRegistry
    private var fileManager: FileManager { .default }

    public init(
        roomSkillsURL: URL? = nil,
        tenantSkillsURL: URL? = nil,
        globalRegistry: SkillRegistry = SkillRegistry()
    ) {
        self.roomSkillsURL = roomSkillsURL
        self.tenantSkillsURL = tenantSkillsURL
        self.globalRegistry = globalRegistry
    }

    /// 스킬 이름으로 단방향 캐스케이드 단건 검색
    public func resolve(name: String) -> ResolvedSkill? {
        resolveRoomLocal(name: name) ?? resolveTenant(name: name) ?? resolveGlobal(name: name)
    }

    private func resolveRoomLocal(name: String) -> ResolvedSkill? {
        guard let roomSkillsURL else { return nil }
        let candidateDir = roomSkillsURL.appendingPathComponent(name, isDirectory: true)
        return resolveFromDirectory(candidateDir, name: name, tool: "room", scope: "room", layer: .roomLocal)
    }

    private func resolveTenant(name: String) -> ResolvedSkill? {
        guard let tenantSkillsURL else { return nil }
        let candidateDir = tenantSkillsURL.appendingPathComponent(name, isDirectory: true)
        return resolveFromDirectory(candidateDir, name: name, tool: "tenant", scope: "tenant", layer: .tenant)
    }

    private func resolveGlobal(name: String) -> ResolvedSkill? {
        guard let globalMatch = globalRegistry.scanGlobal().first(where: { $0.name == name }) else {
            return nil
        }
        return ResolvedSkill(ref: globalMatch, layer: .global)
    }

    /// 사용 가능한 모든 스킬을 계층 우선순위에 맞춰 통합 수집 (중복 이름은 하위 계층이 오버라이드)
    public func resolveAll() -> [ResolvedSkill] {
        var resolvedMap: [String: ResolvedSkill] = [:]

        // 3. Global (가장 낮은 우선순위로 먼저 채움)
        for globalSkill in globalRegistry.scanGlobal() {
            resolvedMap[globalSkill.name] = ResolvedSkill(ref: globalSkill, layer: .global)
        }

        // 2. Tenant (글로벌 오버라이드)
        if let tenantSkillsURL {
            for skill in scanDirectory(tenantSkillsURL, tool: "tenant", scope: "tenant", layer: .tenant) {
                resolvedMap[skill.name] = skill
            }
        }

        // 1. Room Local (최우선 오버라이드)
        if let roomSkillsURL {
            for skill in scanDirectory(roomSkillsURL, tool: "room", scope: "room", layer: .roomLocal) {
                resolvedMap[skill.name] = skill
            }
        }

        return resolvedMap.values.sorted { $0.name < $1.name }
    }

    /// Copy-on-Write: 상위 계층(글로벌/테넌트)의 스킬을 룸 로컬 디렉토리로 안전 복사
    /// 이미 룸 로컬에 존재하면 해당 로컬 버전을 그대로 반환.
    public func materialize(
        skillName: String,
        targetRoomSkillsURL: URL? = nil
    ) throws -> ResolvedSkill {
        guard let destBase = targetRoomSkillsURL ?? roomSkillsURL else {
            throw SkillProxyError.missingTargetDirectory
        }

        let targetDir = destBase.appendingPathComponent(skillName, isDirectory: true)

        // 이미 로컬에 존재하면 즉시 반환
        if let local = resolveFromDirectory(targetDir, name: skillName, tool: "room", scope: "room", layer: .roomLocal) {
            return local
        }

        // 복사할 원본 검색 (Tenant -> Global)
        guard let sourceSkill = resolve(name: skillName) else {
            throw SkillProxyError.skillNotFound(name: skillName)
        }

        try ensureDirectoryExists(destBase)
        try copySourceSkill(from: sourceSkill.path, to: targetDir, skillName: skillName)

        guard let materialized = resolveFromDirectory(targetDir, name: skillName, tool: "room", scope: "room", layer: .roomLocal) else {
            throw SkillProxyError.materializationFailed(name: skillName)
        }

        return materialized
    }

    private func ensureDirectoryExists(_ dir: URL) throws {
        guard !fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func copySourceSkill(from sourcePath: String, to targetDir: URL, skillName: String) throws {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir)

        guard !isDir.boolValue else {
            try fileManager.copyItem(at: sourceURL, to: targetDir)
            return
        }

        let sourceFolder = sourceURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: sourceFolder.path), sourceFolder.lastPathComponent == skillName else {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let destFile = targetDir.appendingPathComponent("SKILL.md")
            try fileManager.copyItem(at: sourceURL, to: destFile)
            return
        }
        try fileManager.copyItem(at: sourceFolder, to: targetDir)
    }

    private func resolveFromDirectory(
        _ dir: URL,
        name: String,
        tool: String,
        scope: String,
        layer: SkillResolutionLayer
    ) -> ResolvedSkill? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let skillFile = SkillRegistry.skillFile(in: dir, fm: fileManager) ?? dir.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillFile.path) else {
            return nil
        }
        let ref = SkillRef(
            id: "\(tool)/\(name)",
            name: name,
            tool: tool,
            path: skillFile.path,
            scope: scope
        )
        return ResolvedSkill(ref: ref, layer: layer)
    }

    private func scanDirectory(
        _ baseDir: URL,
        tool: String,
        scope: String,
        layer: SkillResolutionLayer
    ) -> [ResolvedSkill] {
        guard let entries = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var results: [ResolvedSkill] = []
        for entry in entries {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            if let resolved = resolveFromDirectory(entry, name: name, tool: tool, scope: scope, layer: layer) {
                results.append(resolved)
            }
        }
        return results
    }
}

public enum SkillProxyError: Error, LocalizedError, Equatable {
    case missingTargetDirectory
    case skillNotFound(name: String)
    case materializationFailed(name: String)

    public var errorDescription: String? {
        switch self {
        case .missingTargetDirectory:
            return "Destination room skills directory was not provided."
        case .skillNotFound(let name):
            return "Skill '\(name)' could not be resolved from any cascade layer."
        case .materializationFailed(let name):
            return "Failed to verify materialized skill '\(name)'."
        }
    }
}
