import Foundation

/// TCC.db 에 남은 **확실히 죽은 행** 을 정리한다.
///
/// ## 삭제 대상 (safe)
/// 1. **사용자 db 의 시스템 스코프 서비스 행** — FDA·손쉬운 사용·화면 기록·입력 모니터링·
///    PostEvent 는 시스템 db 에서만 강제된다. 사용자 db 행은 효과가 없다.
/// 2. **고아 null-csreq 행** — 번들이 디스크에 없고 `csreq` 가 비어 있는 클라이언트.
///    앱이 없으면 권한 행이 의미 없고, csreq 없으면 TCC 가 무시하는 경우가 많아
///    정리해도 동작 중인 권한을 회수할 위험이 낮다(2026-08-01 실측·정리).
///
/// ## 보고만 (삭제 안 함)
/// 번들이 **남아 있는데** 사용자 스코프 `csreq NULL` 인 행 — grant 로 덮어쓸 수 있다.
/// 유효 여부를 100% 단정하지 못해 기본 prune 에서는 지우지 않는다.
public struct TCCPruner: Sendable {
    public var userDBPath: String
    /// 번들 존재 판정. 테스트에서 주입한다.
    public var bundleExists: @Sendable (String) -> Bool

    public init(
        userDBPath: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        bundleExists: @escaping @Sendable (String) -> Bool = TCCPruner.liveBundleExists
    ) {
        self.userDBPath = userDBPath
        self.bundleExists = bundleExists
    }

    /// LaunchServices + 경로 존재로 번들 유무 판정.
    public static let liveBundleExists: @Sendable (String) -> Bool = { bundleID in
        guard let path = TCCGranter.bundlePath(forBundleID: bundleID) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// 사용자 db 에 있으면 확실히 죽은 서비스 키.
    public static var deadInUserDBServiceKeys: [String] {
        TCCService.allCases.filter(\.isSystemScoped).map(\.tccDatabaseKey)
    }

    public struct Report: Sendable, Codable {
        /// 서비스 키 → 사용자 db 시스템 스코프 죽은 행 수.
        public var deadRows: [String: Int]
        /// 서비스 키 → 고아(번들 없음) null-csreq 행 수.
        public var orphanRows: [String: Int]
        /// 고아 클라이언트 수(고유).
        public var orphanClientCount: Int
        /// 서비스 키 → 번들이 사라진 클라이언트의 행 수(csreq 유무 무관).
        public var deadBundleRows: [String: Int]
        /// 서비스 키 → 번들은 있는데 csreq 없는 사용자 스코프 행(보고만).
        public var suspectRows: [String: Int]
        /// 삭제를 실제로 수행했다면 백업 경로.
        public var backupPath: String?
        /// 삭제한 행 수. dry-run 이면 nil.
        public var deletedRows: Int?

        public var deadTotal: Int { deadRows.values.reduce(0, +) }
        public var deadBundleTotal: Int { deadBundleRows.values.reduce(0, +) }
        public var orphanTotal: Int { orphanRows.values.reduce(0, +) }
        public var suspectTotal: Int { suspectRows.values.reduce(0, +) }
        /// apply 시 지울 총량(죽은 시스템 스코프 + 고아 null-csreq + 번들 사라진 행).
        /// 겹치므로 상한이 아니라 근사치다 — 실제 삭제 수는 `deletedRows` 가 정본.
        public var deletableTotal: Int { deadTotal + orphanTotal + deadBundleTotal }

        public init(deadRows: [String: Int], orphanRows: [String: Int] = [:],
                    orphanClientCount: Int = 0, deadBundleRows: [String: Int] = [:],
                    suspectRows: [String: Int],
                    backupPath: String? = nil, deletedRows: Int? = nil) {
            self.deadRows = deadRows
            self.orphanRows = orphanRows
            self.orphanClientCount = orphanClientCount
            self.deadBundleRows = deadBundleRows
            self.suspectRows = suspectRows
            self.backupPath = backupPath
            self.deletedRows = deletedRows
        }

        // computed 합계를 JSON 에도 실어 에이전트가 한 번에 읽게 한다.
        private enum CodingKeys: String, CodingKey {
            case deadRows, orphanRows, orphanClientCount, deadBundleRows, suspectRows
            case backupPath, deletedRows
            case deadTotal, orphanTotal, suspectTotal, deletableTotal, deadBundleTotal
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(deadRows, forKey: .deadRows)
            try c.encode(orphanRows, forKey: .orphanRows)
            try c.encode(orphanClientCount, forKey: .orphanClientCount)
            try c.encode(deadBundleRows, forKey: .deadBundleRows)
            try c.encode(deadBundleTotal, forKey: .deadBundleTotal)
            try c.encode(suspectRows, forKey: .suspectRows)
            try c.encodeIfPresent(backupPath, forKey: .backupPath)
            try c.encodeIfPresent(deletedRows, forKey: .deletedRows)
            try c.encode(deadTotal, forKey: .deadTotal)
            try c.encode(orphanTotal, forKey: .orphanTotal)
            try c.encode(suspectTotal, forKey: .suspectTotal)
            try c.encode(deletableTotal, forKey: .deletableTotal)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            deadRows = try c.decode([String: Int].self, forKey: .deadRows)
            orphanRows = try c.decodeIfPresent([String: Int].self, forKey: .orphanRows) ?? [:]
            orphanClientCount = try c.decodeIfPresent(Int.self, forKey: .orphanClientCount) ?? 0
            deadBundleRows = try c.decodeIfPresent([String: Int].self, forKey: .deadBundleRows) ?? [:]
            suspectRows = try c.decode([String: Int].self, forKey: .suspectRows)
            backupPath = try c.decodeIfPresent(String.self, forKey: .backupPath)
            deletedRows = try c.decodeIfPresent(Int.self, forKey: .deletedRows)
        }
    }

    /// 삭제하지 않고 무엇이 대상인지만 조사한다.
    public func inspect() -> Report? {
        guard FileManager.default.fileExists(atPath: userDBPath) else { return nil }

        var dead: [String: Int] = [:]
        for key in Self.deadInUserDBServiceKeys {
            let count = rowCount(where: "service='\(key)'")
            if count > 0 { dead[key] = count }
        }

        let systemKeys = Set(Self.deadInUserDBServiceKeys)
        let orphanClients = Self.orphanClientIDs(
            dbPath: userDBPath, bundleExists: bundleExists)

        var orphan: [String: Int] = [:]
        if !orphanClients.isEmpty {
            // 고아 클라이언트의 null-csreq 행을 서비스별로 센다.
            for service in TCCService.allCases {
                let key = service.tccDatabaseKey
                let count = rowCount(where: """
                service='\(key)' and (csreq is null or length(csreq)=0) \
                and client in (\(Self.sqlList(orphanClients)))
                """)
                if count > 0 { orphan[key] = count }
            }
            // 카탈로그 밖 서비스도 잡는다(Liverpool·Ubiquity 등).
            let extra = rowCount(where: """
            (csreq is null or length(csreq)=0) \
            and client in (\(Self.sqlList(orphanClients))) \
            and service not in (\(Self.sqlList(TCCService.allCases.map(\.tccDatabaseKey))))
            """)
            if extra > 0 { orphan["(other)"] = (orphan["(other)"] ?? 0) + extra }
        }

        var suspect: [String: Int] = [:]
        for service in TCCService.allCases where !systemKeys.contains(service.tccDatabaseKey) {
            // 번들이 남아 있는 클라이언트의 null-csreq 만 의심으로.
            let clause: String
            if orphanClients.isEmpty {
                clause = "service='\(service.tccDatabaseKey)' and (csreq is null or length(csreq)=0)"
            } else {
                clause = """
                service='\(service.tccDatabaseKey)' and (csreq is null or length(csreq)=0) \
                and client not in (\(Self.sqlList(orphanClients)))
                """
            }
            let count = rowCount(where: clause)
            if count > 0 { suspect[service.tccDatabaseKey] = count }
        }

        // 번들이 사라진 클라이언트의 행 — csreq 가 살아 있어도 좀비다.
        var deadBundle: [String: Int] = [:]
        let deadClients = Self.deadBundleClientIDs(dbPath: userDBPath, bundleExists: bundleExists)
        if !deadClients.isEmpty {
            guard let raw = TCCGranter.runTool("/usr/bin/sqlite3", [
                "-readonly", userDBPath,
                "select service,count(*) from access where client in (\(Self.sqlList(deadClients))) group by service;"
            ]) else { return Report(deadRows: dead, orphanRows: orphan,
                                    orphanClientCount: orphanClients.count, suspectRows: suspect) }
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: "|")
                guard parts.count >= 2, let n = Int(parts[1]) else { continue }
                deadBundle[String(parts[0])] = n
            }
        }

        return Report(
            deadRows: dead,
            orphanRows: orphan,
            orphanClientCount: orphanClients.count,
            deadBundleRows: deadBundle,
            suspectRows: suspect)
    }

    /// 죽은 시스템 스코프 행 + 고아 null-csreq 를 삭제한다. **삭제 전 백업.**
    public func prune() -> Report? {
        guard var report = inspect() else { return nil }
        guard report.deletableTotal > 0 else {
            report.deletedRows = 0
            return report
        }

        guard let backup = backupDatabase() else {
            // 백업 없이는 지우지 않는다.
            return report
        }
        report.backupPath = backup

        let beforeTotal = totalRows()
        let keys = Self.deadInUserDBServiceKeys.map { "'\($0)'" }.joined(separator: ",")
        // 1) 시스템 스코프 in user db
        _ = TCCGranter.runTool(
            "/usr/bin/sqlite3",
            [userDBPath, "delete from access where service in (\(keys));"])

        // 2-1) 번들이 사라진 클라이언트의 모든 행 (csreq 유무 무관)
        let deadClients = Self.deadBundleClientIDs(dbPath: userDBPath, bundleExists: bundleExists)
        if !deadClients.isEmpty {
            _ = TCCGranter.runTool(
                "/usr/bin/sqlite3",
                [userDBPath,
                 "delete from access where client in (\(Self.sqlList(deadClients)));"])
        }

        // 2) 고아 null-csreq
        let orphans = Self.orphanClientIDs(dbPath: userDBPath, bundleExists: bundleExists)
        if !orphans.isEmpty {
            _ = TCCGranter.runTool(
                "/usr/bin/sqlite3",
                [userDBPath, """
                delete from access where (csreq is null or length(csreq)=0) \
                and client in (\(Self.sqlList(orphans)));
                """])
        }

        let afterTotal = totalRows()
        report.deletedRows = max(0, beforeTotal - afterTotal)

        // 재조사로 잔여를 갱신한다.
        if let after = inspect() {
            report.deadRows = after.deadRows
            report.orphanRows = after.orphanRows
            report.orphanClientCount = after.orphanClientCount
            report.suspectRows = after.suspectRows
        }
        return report
    }

    // MARK: - 내부

    private func totalRows() -> Int {
        guard let out = TCCGranter.runTool(
            "/usr/bin/sqlite3",
            ["-readonly", userDBPath, "select count(*) from access;"]) else { return 0 }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func rowCount(where clause: String) -> Int {
        guard let out = TCCGranter.runTool(
            "/usr/bin/sqlite3",
            ["-readonly", userDBPath, "select count(*) from access where \(clause);"]) else { return 0 }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// null-csreq 를 가진 클라이언트 중 번들이 없는 것.
    /// 우리가 소유한 bundleID 접두어. **이 범위 밖은 지우지 않는다.**
    ///
    /// 왜 필수인가 (실측 2026-08-08): "번들이 없으면 죽었다" 만으로 판정하니 164건이
    /// 나왔는데 그 안에 `com.apple.ScreenTimeAgent`,
    /// `com.apple.accessibility.AccessibilityUIServer` 같은 **시스템 데몬 47건**이 섞였다.
    /// 데몬·XPC 서비스는 `.app` 이 아니라 LaunchServices 로 해석되지 않을 뿐 살아 있다.
    /// 그걸 지우면 macOS 기능이 깨진다. 서드파티 36건도 우리가 판단할 근거가 없다.
    public static let ownedBundlePrefixes = ["net.ranode.", "com.dalsoop.", "local."]

    public static func isOwned(_ client: String, prefixes: [String]) -> Bool {
        prefixes.contains { client.hasPrefix($0) }
    }

    /// 번들이 사라진 **우리 앱** 클라이언트 — csreq 유무와 무관하게 전부.
    ///
    /// 경로형 클라이언트(`/opt/homebrew/bin/...`)는 파일 부재로 판정한다 — 소유 여부를
    /// 접두어로 알 수 없지만, 그 경로에 파일이 없으면 그 등록은 확실히 죽은 것이다.
    ///
    /// `orphanClientIDs` 는 csreq 가 null 인 행만 봐서, 정상 서명으로 부여받고 앱만 사라진
    /// 행(대다수)을 놓친다. 실측 2026-08-08: 좀비 114건 중 98건이 그 부류였고
    /// (documents-folder), prune 은 45건(고아)만 지울 수 있다고 보고했다.
    ///
    /// 이 행을 지우는 게 위생인 이유: 같은 bundleID 로 다시 빌드하면 **프롬프트 없이 권한을
    /// 물려받는다**(doctor 의 ZOMBIE-DEV-BUILD 경고가 정확히 이 위험이다).
    static func deadBundleClientIDs(
        dbPath: String,
        bundleExists: @Sendable (String) -> Bool,
        ownedPrefixes: [String] = ownedBundlePrefixes
    ) -> [String] {
        guard let out = TCCGranter.runTool(
            "/usr/bin/sqlite3",
            ["-readonly", dbPath, "select distinct client from access;"])
        else { return [] }
        return out
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            // 경로형 클라이언트(/opt/homebrew/bin/... )는 번들이 아니다 — 파일 존재로 판정한다.
            .filter { client in
                guard !client.isEmpty else { return false }
                if client.hasPrefix("/") { return !FileManager.default.fileExists(atPath: client) }
                // 소유 범위 밖(com.apple.*, 서드파티)은 판정하지 않는다.
                guard Self.isOwned(client, prefixes: ownedPrefixes) else { return false }
                return !bundleExists(client)
            }
    }

    static func orphanClientIDs(
        dbPath: String,
        bundleExists: @Sendable (String) -> Bool
    ) -> [String] {
        guard let out = TCCGranter.runTool(
            "/usr/bin/sqlite3",
            ["-readonly", dbPath,
             "select distinct client from access where csreq is null or length(csreq)=0;"])
        else { return [] }
        return out
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !bundleExists($0) }
    }

    static func sqlList(_ values: [String]) -> String {
        values.map { TCCGranter.sqlQuoted($0) }.joined(separator: ",")
    }

    /// sqlite `.backup` 으로 일관된 스냅샷을 만든다. 파일 복사는 WAL 때문에 안전하지 않다.
    private func backupDatabase() -> String? {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let dest = (userDBPath as NSString)
            .appendingPathExtension("bak-prune-\(stamp)") ?? "\(userDBPath).bak-prune-\(stamp)"

        guard TCCGranter.runTool("/usr/bin/sqlite3", [userDBPath, ".backup '\(dest)'"]) != nil,
              FileManager.default.fileExists(atPath: dest) else { return nil }
        return dest
    }
}
