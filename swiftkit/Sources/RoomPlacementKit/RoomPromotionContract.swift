import Foundation

/// 승격 대상 스코프 (테넌트 또는 전역 모노레포)
public enum PromotionScope: Codable, Sendable, Equatable {
    case tenant(String)
    case global

    public var identifier: String {
        switch self {
        case .tenant(let slug): return "tenant:\(slug)"
        case .global: return "global"
        }
    }
}

/// 승격 시 충돌 사유
public enum PromotionConflict: Codable, Sendable, Equatable {
    case collision(skillName: String, diffSummary: String)
    case missingCandidate(name: String)
    case ruleViolation(rule: String, detail: String)
}

/// 승격 사전 검사 결과
public enum PromotionVerdict: Sendable, Equatable {
    case ready(autoMerge: Bool)
    case conflict(PromotionConflict)
}

/// 상위 승격 충돌 해결 정책 ("컨플릭은 위에서 관리")
public enum PromotionConflictPolicy: String, Codable, Sendable, Equatable {
    /// 기본값: 충돌 감지 시 에러 투척 (안전 모드)
    case reject
    /// 강제 덮어쓰기
    case force
    /// 자동 마이너 버전 승격 (e.g. 1.0.0 -> 1.1.0)
    case autoBump
}

/// 승격 완료 영수증 (위키/원장 및 룸에 보존되는 단 1장의 불변 증명서)
public struct RoomPromotionReceipt: Codable, Sendable, Equatable {
    public let receiptID: String
    public let roomID: String
    public let tenant: String
    public let scope: PromotionScope
    public let skillName: String
    public let promotedAt: Date
    public let contentSHA256: String
    public let checkerOutcome: String
    public let resolution: String?

    public init(
        receiptID: String = "rcpt:\(UUID().uuidString.prefix(12).lowercased())",
        roomID: String,
        tenant: String,
        scope: PromotionScope,
        skillName: String,
        promotedAt: Date = Date(),
        contentSHA256: String,
        checkerOutcome: String = "verified",
        resolution: String? = nil
    ) {
        self.receiptID = receiptID
        self.roomID = roomID
        self.tenant = tenant
        self.scope = scope
        self.skillName = skillName
        self.promotedAt = promotedAt
        self.contentSHA256 = contentSHA256
        self.checkerOutcome = checkerOutcome
        self.resolution = resolution
    }
}

/// 승격 게이트 — 하위 룸의 스킬을 상위(테넌트/전역)로 올릴 때 충돌을 검사하고 병합
public struct RoomPromotionGate: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    /// 승격 사전 판정 (Dry-run)
    public func evaluate(
        skillName: String,
        in layout: RoomVaultLayout,
        targetDirectory: URL
    ) -> PromotionVerdict {
        let localSkillFile = layout.skillsDir.appendingPathComponent(skillName).appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: localSkillFile.path) else {
            return .conflict(.missingCandidate(name: skillName))
        }

        let targetSkillFile = targetDirectory.appendingPathComponent(skillName).appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: targetSkillFile.path) else {
            return .ready(autoMerge: true)
        }

        var localData = Data()
        var targetData = Data()
        do {
            localData = try Data(contentsOf: localSkillFile)
            targetData = try Data(contentsOf: targetSkillFile)
        } catch {
            return .conflict(.collision(skillName: skillName, diffSummary: "unreadable: \(error)"))
        }

        guard localData != targetData else {
            return .ready(autoMerge: true)
        }

        let summary = "local=\(localData.count) bytes vs target=\(targetData.count) bytes"
        return .conflict(.collision(skillName: skillName, diffSummary: summary))
    }

    /// 승격 실행: 타겟 디렉토리로 안전 복사 후 영수증 발행 ("컨플릭은 위에서 관리")
    public func promote(
        skillName: String,
        roomID: String,
        tenant: String,
        in layout: RoomVaultLayout,
        targetDirectory: URL,
        scope: PromotionScope,
        forceMerge: Bool = false,
        conflictPolicy: PromotionConflictPolicy = .reject
    ) throws -> RoomPromotionReceipt {
        try validateScope(scope, for: tenant)

        let targetSkillFolder = targetDirectory.appendingPathComponent(skillName)
        let targetSkillFile = targetSkillFolder.appendingPathComponent("SKILL.md")
        let localSkillFolder = layout.skillsDir.appendingPathComponent(skillName)
        let localSkillFile = localSkillFolder.appendingPathComponent("SKILL.md")

        let effectivePolicy: PromotionConflictPolicy = forceMerge ? .force : conflictPolicy
        let resolution = try resolvePromotionTarget(
            targetSkillFile: targetSkillFile,
            localSkillFile: localSkillFile,
            policy: effectivePolicy,
            skillName: skillName,
            layout: layout,
            targetDirectory: targetDirectory
        )

        try atomicDeploy(from: localSkillFolder, to: targetSkillFolder, in: targetDirectory)

        let skillFile = targetSkillFolder.appendingPathComponent("SKILL.md")
        var data = Data()
        do {
            data = try Data(contentsOf: skillFile)
        } catch {
            data = Data()
        }
        let sha = data.map { String(format: "%02x", $0) }.joined()

        let receipt = RoomPromotionReceipt(
            roomID: roomID,
            tenant: tenant,
            scope: scope,
            skillName: skillName,
            contentSHA256: String(sha.prefix(32)),
            checkerOutcome: "verified",
            resolution: resolution
        )

        try saveReceipt(receipt, skillName: skillName, in: layout)
        return receipt
    }

    private func resolvePromotionTarget(
        targetSkillFile: URL,
        localSkillFile: URL,
        policy: PromotionConflictPolicy,
        skillName: String,
        layout: RoomVaultLayout,
        targetDirectory: URL
    ) throws -> String {
        guard fileManager.fileExists(atPath: targetSkillFile.path) else {
            return "fresh"
        }

        var localData = Data()
        var targetData = Data()
        do {
            localData = try Data(contentsOf: localSkillFile)
            targetData = try Data(contentsOf: targetSkillFile)
        } catch {
            localData = Data()
            targetData = Data()
        }

        if !localData.isEmpty && localData == targetData {
            return "identical"
        }

        switch policy {
        case .reject:
            let verdict = evaluate(skillName: skillName, in: layout, targetDirectory: targetDirectory)
            if case .conflict(let err) = verdict {
                throw PromotionGateError.unresolvedConflict(err)
            }
            return "fresh"
        case .force:
            return "forced"
        case .autoBump:
            return try applyAutoBump(targetFile: targetSkillFile, localFile: localSkillFile)
        }
    }

    private func applyAutoBump(targetFile: URL, localFile: URL) throws -> String {
        var targetText = ""
        var localText = ""
        do {
            targetText = try String(contentsOf: targetFile, encoding: .utf8)
            localText = try String(contentsOf: localFile, encoding: .utf8)
        } catch {
            targetText = ""
            localText = ""
        }
        let currentVersion = RoomPromotionGate.extractVersion(from: targetText)
            ?? RoomPromotionGate.extractVersion(from: localText)
            ?? "1.0.0"
        let bumpedVersion = RoomPromotionGate.bumpMinorVersion(currentVersion)
        let bumpedContent = RoomPromotionGate.applyVersion(to: localText, newVersion: bumpedVersion)
        try bumpedContent.write(to: localFile, atomically: true, encoding: .utf8)
        return "auto_bump:\(currentVersion)->\(bumpedVersion)"
    }

    public static func extractVersion(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version:") {
                let val = trimmed.dropFirst("version:".count).trimmingCharacters(in: .whitespaces)
                let cleaned = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    public static func bumpMinorVersion(_ version: String) -> String {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        if parts.count >= 2 {
            let major = parts[0]
            let minor = parts[1] + 1
            return "\(major).\(minor).0"
        } else if let single = parts.first {
            return "\(single).1.0"
        }
        return "1.1.0"
    }

    private static func insertFrontmatterVersion(_ lines: [String], newVersion: String) -> [String] {
        var updated = lines
        if updated.first?.trimmingCharacters(in: .whitespaces) == "---" {
            updated.insert("version: \(newVersion)", at: 1)
        } else {
            updated.insert(contentsOf: ["---", "version: \(newVersion)", "---"], at: 0)
        }
        return updated
    }

    public static func applyVersion(to content: String, newVersion: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var updated: [String] = []
        var replaced = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version:") && !replaced {
                updated.append("version: \(newVersion)")
                replaced = true
            } else {
                updated.append(line)
            }
        }
        if !replaced {
            updated = insertFrontmatterVersion(updated, newVersion: newVersion)
        }
        return updated.joined(separator: "\n")
    }

    private func validateScope(_ scope: PromotionScope, for tenant: String) throws {
        switch scope {
        case .tenant(let targetTenant):
            guard targetTenant == tenant else {
                throw PromotionGateError.unauthorizedScope(scope: scope, callerTenant: tenant)
            }
        case .global:
            break
        }
    }

    private func atomicDeploy(from source: URL, to target: URL, in parent: URL) throws {
        guard fileManager.fileExists(atPath: parent.path) else {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
            return
        }

        let tempID = UUID().uuidString.prefix(8).lowercased()
        let tempFolder = parent.appendingPathComponent(".tmp_\(target.lastPathComponent)_\(tempID)")
        try fileManager.copyItem(at: source, to: tempFolder)

        guard fileManager.fileExists(atPath: target.path) else {
            try moveItemSafely(from: tempFolder, to: target)
            return
        }

        let backupFolder = parent.appendingPathComponent(".bak_\(target.lastPathComponent)_\(tempID)")
        try moveItemSafely(from: target, to: backupFolder)
        do {
            try moveItemSafely(from: tempFolder, to: target)
            try removeItemSafely(at: backupFolder)
        } catch {
            do {
                try moveItemSafely(from: backupFolder, to: target)
            } catch {
                fputs("warning: rollback target move failed: \(error)\n", stderr)
            }
            do {
                try removeItemSafely(at: tempFolder)
            } catch {
                fputs("warning: tempFolder cleanup failed: \(error)\n", stderr)
            }
            throw error
        }
    }

    private func moveItemSafely(from source: URL, to dest: URL) throws {
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: source, to: dest)
    }

    private func removeItemSafely(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func saveReceipt(_ receipt: RoomPromotionReceipt, skillName: String, in layout: RoomVaultLayout) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let receiptData = try encoder.encode(receipt)

        guard fileManager.fileExists(atPath: layout.receiptsDir.path) else {
            try fileManager.createDirectory(at: layout.receiptsDir, withIntermediateDirectories: true)
            try receiptData.write(to: layout.receiptFile(for: skillName), options: .atomic)
            try receiptData.write(to: layout.receiptFile, options: .atomic)
            return
        }

        try receiptData.write(to: layout.receiptFile(for: skillName), options: .atomic)
        try receiptData.write(to: layout.receiptFile, options: .atomic)
    }
}

public enum PromotionGateError: Error, LocalizedError, Equatable {
    case unresolvedConflict(PromotionConflict)
    case unauthorizedScope(scope: PromotionScope, callerTenant: String)

    public var errorDescription: String? {
        switch self {
        case .unresolvedConflict(let conflict):
            return "Cannot promote skill due to unresolved conflict: \(conflict)"
        case .unauthorizedScope(let scope, let tenant):
            return "Tenant '\(tenant)' is not authorized to promote to scope '\(scope.identifier)'."
        }
    }
}
