import Foundation
import LocalizationKit

// 카드를 **만드는** 쪽. 어휘(`Need`·`Card`·`OpsPriority`)는 `SeatOps.swift` 에 있다 —
// 자리를 읽기만 하는 앱은 어휘만 보고, 계산은 이 파일이 진다.

extension SeatOps {
    /// 재직 자리 카드 구성. 니즈 심한 순 → 핸들.
    public static func cards(
        seats: [Seat],
        health: [String: SeatHealth],
        board: [SeatBoardRow],
        extraNeeds: (Seat) -> [Need] = { _ in [] },
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> [Card] {
        let boardByHandle = Dictionary(uniqueKeysWithValues: board.map { ($0.handle.lowercased(), $0) })
        return seats.map { seat in
            let h = health[seat.handle]
            let row = boardByHandle[seat.handle.lowercased()]
            let shared = row?.sharedPath ?? false
            let peers = row?.sharedWith ?? []
            var needs = needs(for: seat, health: h, sharedPath: shared, sharedWith: peers)
            needs.append(contentsOf: extraNeeds(seat))
            let activity = activity(for: seat, fileManager: fileManager, now: now)
            let feedback = feedback(for: seat, health: h, sharedPath: shared)
            return Card(
                seat: seat,
                status: .employed,
                health: h,
                sharedPath: shared,
                sharedWith: peers,
                needs: needs,
                activity: activity,
                feedback: feedback
            )
        }
        .sorted(by: opsSort)
    }

    /// 운영 우선순위 정렬 (테스트·UI 공유).
    public static func opsSort(_ a: Card, _ b: Card) -> Bool { a.opsPriority < b.opsPriority }

    public static func needs(
        for seat: Seat,
        health: SeatHealth?,
        sharedPath: Bool,
        sharedWith: [String]
    ) -> [Need] {
        var out: [Need] = []
        if seat.keys == nil {
            out.append(Need(kind: "keys", summary: "tenant·vault 미바인딩", severity: .warn))
        }
        if case .none = seat.workspace {
            out.append(Need(kind: "workspace", summary: "작업 경로 없음 (조회 전용)", severity: .info))
        }
        if sharedPath {
            let peers = sharedWith.map { "@\($0)" }.joined(separator: ", ")
            out.append(Need(
                kind: "shared",
                summary: peers.isEmpty ? "경로 공유 충돌" : "경로 공유: \(peers)",
                severity: .blocker
            ))
        }
        for issue in health?.issues ?? [] {
            let sev: Need.Severity = issue.contains("없음") || issue.contains("막힘") ? .blocker : .warn
            out.append(Need(kind: "health", summary: issue, severity: sev))
        }
        // workdir 의 NEEDS.md / SEAT.md 첫 줄 (있으면)
        if let note = seatFileNote(in: seat.workspace.directory) { out.append(note) }
        return out
    }

    /// 자리 폴더의 메모 파일 첫 줄을 니즈 하나로 접는다.
    ///
    /// 먼저 **발견된 파일 하나만** 본다 — 파일이 있으면 내용이 비어도 거기서 멈춘다(옛 `break`).
    static func seatFileNote(in directory: String?) -> Need? {
        guard let directory else { return nil }
        for name in ["NEEDS.md", "needs.md", "SEAT.md"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            guard let text = readUTF8(url) else { continue }
            guard let line = firstMeaningfulLine(text), !line.isEmpty else { return nil }
            // SEAT.md 는 메모, NEEDS.md 본문만 약한 니즈(info) — 헤더 니즈 카운트 제외
            let kind = name.lowercased().hasPrefix("need") ? "needs-file" : "file"
            return Need(
                kind: kind,
                summary: "\(name): \(String(line.prefix(80)))",
                severity: .info
            )
        }
        return nil
    }

    /// 주석(`#`)도 빈 줄도 아닌 첫 줄.
    static func firstMeaningfulLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func activity(
        for seat: Seat,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> Activity {
        let days = max(0, Calendar.current.dateComponents([.day], from: seat.hiredAt, to: now).day ?? 0)
        guard let dir = seat.workspace.directory else {
            return Activity(
                workdirModifiedAt: nil,
                gitHeadModifiedAt: nil,
                seatMarkdownPresent: false,
                recentFileTouches: 0,
                daysSinceHire: days,
                summary: days > 0 ? "작업 경로 없음 · 고용 \(days)일" : "작업 경로 없음"
            )
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return Activity(
                workdirModifiedAt: nil,
                gitHeadModifiedAt: nil,
                seatMarkdownPresent: false,
                recentFileTouches: 0,
                daysSinceHire: days,
                summary: "경로 없음/마운트 끊김"
            )
        }
        let attrs = itemAttributes(fileManager, dir)
        let mtime = attrs?[.modificationDate] as? Date
        let seatMd = fileManager.fileExists(atPath: (dir as NSString).appendingPathComponent("SEAT.md"))
        let gitMtime = gitHeadMtime(in: dir, fileManager: fileManager)
        let recent = recentTouches(in: dir, since: now.addingTimeInterval(-7 * 24 * 3600), fileManager: fileManager)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        var parts: [String] = []
        if let gitMtime {
            parts.append("git \(formatter.localizedString(for: gitMtime, relativeTo: now))")
        }
        if let mtime {
            parts.append("dir \(formatter.localizedString(for: mtime, relativeTo: now))")
        }
        if recent > 0 {
            parts.append("7일 \(recent)파일")
        }
        if seatMd {
            parts.append("SEAT.md")
        }
        if days > 0 {
            parts.append("고용 \(days)일")
        }
        let summary: String
        if parts.isEmpty {
            summary = "활동 신호 약함"
        } else {
            summary = parts.joined(separator: " · ")
        }
        return Activity(
            workdirModifiedAt: mtime,
            gitHeadModifiedAt: gitMtime,
            seatMarkdownPresent: seatMd,
            recentFileTouches: recent,
            daysSinceHire: days,
            summary: summary
        )
    }

    public static func feedback(
        for seat: Seat,
        health: SeatHealth?,
        sharedPath: Bool
    ) -> Feedback {
        var auto: [String] = []
        if sharedPath { auto.append("경로 공유 — rebind 필요") }
        for issue in health?.issues ?? [] { auto.append(issue) }
        if let note = seat.note, !note.isEmpty {
            return Feedback(humanNote: note, autoLines: auto)
        }
        return Feedback(humanNote: nil, autoLines: auto)
    }

    /// `.git/logs/HEAD` 또는 `.git/HEAD` mtime — git 프로세스 없이 관측.
    public static func gitHeadMtime(in dir: String, fileManager: FileManager = .default) -> Date? {
        let git = (dir as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        // worktree: .git 이 파일일 수 있음
        if fileManager.fileExists(atPath: git, isDirectory: &isDir) {
            if isDir.boolValue {
                let log = (git as NSString).appendingPathComponent("logs/HEAD")
                if let d = (try? fileManager.attributesOfItem(atPath: log))?[.modificationDate] as? Date {
                    return d
                }
                let head = (git as NSString).appendingPathComponent("HEAD")
                return (try? fileManager.attributesOfItem(atPath: head))?[.modificationDate] as? Date
            }
            // gitdir 포인터 파일 — mtime 만
            return (try? fileManager.attributesOfItem(atPath: git))?[.modificationDate] as? Date
        }
        return nil
    }

    /// 얕은 디렉터리 스캔 — 깊이 2, 최대 200 항목. `.git` 스킵.
    private static func recentTouches(
        in dir: String,
        since: Date,
        fileManager: FileManager
    ) -> Int {
        let root = URL(fileURLWithPath: dir)
        var count = 0
        var seen = 0
        guard let en = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        while let item = en.nextObject() as? URL {
            seen += 1
            if seen > recentTouchScanCap { break }
            if item.lastPathComponent == ".git" { en.skipDescendants(); continue }
            if en.level > 2 { en.skipDescendants(); continue }
            let vals = resourceVals(item)
            if vals?.isDirectory ?? false { continue }
            if let m = vals?.contentModificationDate, m >= since { count += 1 }
        }
        return count
    }

    private static let recentTouchScanCap = 200

    private static func readUTF8(_ url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func itemAttributes(_ fileManager: FileManager, _ path: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            return nil
        }
    }

    private static func resourceVals(_ item: URL) -> URLResourceValues? {
        do {
            return try item.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
        } catch {
            return nil
        }
    }

    /// 원장 키에서 `tenant:` 접두만 뗀 slug.
    public static func shortTenant(_ raw: String?) -> String {
        (raw ?? "—").replacingOccurrences(of: "tenant:", with: "")
    }

    /// UI에 찍는 테넌트 이름. Vault 원장 이름 맵이 있으면 그걸 우선.
    /// 폴백: 알려진 slug 한글 · 그 외 slug 그대로.
    public static func tenantLabel(_ raw: String?, vaultNames: [String: String] = [:]) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        if let n = vaultNames[raw], !n.isEmpty { return n }
        let slug = shortTenant(raw)
        if let n = vaultNames["tenant:\(slug)"], !n.isEmpty { return n }
        // name lookup by any vaultNames value keyed loosely
        for (k, v) in vaultNames where shortTenant(k) == slug && !v.isEmpty {
            return v
        }
        switch slug.lowercased() {
        case "personal": return CLILocalization.string("tenant.personal")
        case "family": return CLILocalization.string("tenant.family")
        case "silneobal": return CLILocalization.string("tenant.silneobal")
        case "work", "workspace": return CLILocalization.string("tenant.work")
        case "shared": return CLILocalization.string("filter.shared")
        case "—", "", "-": return "—"
        default: return slug
        }
    }

    /// 해고 시트 캡션 — keepWorkspace/deleteBranch/force 조합에 따른 설명 문구.
    public static func fireCaption(keepWorkspace: Bool, deleteBranch: Bool, force: Bool) -> String {
        if keepWorkspace {
            return CLILocalization.string("fire.caption.keep")
        }
        var parts = ["worktree 회수 시도 후 원장에서 지운다."]
        if deleteBranch { parts.append("브랜치도 삭제한다.") }
        if force {
            parts.append("회수 실패해도 원장에서 지운다.")
        } else {
            parts.append("회수 실패 시 자리는 남는다.")
        }
        return parts.joined(separator: " ")
    }
}
