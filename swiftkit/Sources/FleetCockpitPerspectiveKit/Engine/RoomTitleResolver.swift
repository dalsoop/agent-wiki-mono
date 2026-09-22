import Foundation

/// 방 고유 속성(blueprintSlug, task, occupant, occupantHandle)을 기반으로
/// Plan 전체 타이틀 복제 오염을 차단하고 방의 의미 있는 정본 타이틀을 결정론적으로 추출하는 리졸버
public enum RoomTitleResolver {

    private static let standingKeywords = ["상주 지휘", "command-room", "지휘실"]

    public static func isStandingCommandPlan(_ planTitle: String) -> Bool {
        for kw in standingKeywords where planTitle.contains(kw) {
            return true
        }
        return false
    }

    private static func resolveDirectTitle(roomDict: [String: Any]?, planTitle: String) -> String? {
        guard let roomDict else { return nil }
        if let directTask = (roomDict["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !directTask.isEmpty {
            return directTask
        }
        guard let directTitle = (roomDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !directTitle.isEmpty, directTitle != planTitle else {
            return nil
        }
        return directTitle
    }

    private static func resolveBlueprintTitle(blueprintSlug: String, occupantHandle: String) -> String? {
        let cleanSlug = blueprintSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSlug.isEmpty, cleanSlug != "default" else { return nil }

        let words = cleanSlug
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst().lowercased()
            }
        let readable = words.joined(separator: " ")
        let handle = occupantHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? readable : "\(readable) (\(handle))"
    }

    private static func resolveOccupantTitle(occupantHandle: String, occupant: String) -> String? {
        let handle = occupantHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard handle.isEmpty else { return "\(handle)의 방" }

        let occ = occupant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !occ.isEmpty else { return nil }

        let name = occ.replacingOccurrences(of: "agent:", with: "").components(separatedBy: "@").first ?? ""
        return name.isEmpty ? nil : "\(name)의 방"
    }

    public static func resolveTitle(
        roomDict: [String: Any]? = nil,
        planTitle: String = "",
        blueprintSlug: String = "",
        occupantHandle: String = "",
        occupant: String = "",
        rawTitle: String = ""
    ) -> String {
        let candidates: [() -> String?] = [
            { resolveDirectTitle(roomDict: roomDict, planTitle: planTitle) },
            {
                let trimmed = planTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                return (!trimmed.isEmpty && !isStandingCommandPlan(trimmed)) ? trimmed : nil
            },
            {
                let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                return (!trimmed.isEmpty && !trimmed.contains("상주 지휘") && trimmed != planTitle) ? trimmed : nil
            },
            { resolveBlueprintTitle(blueprintSlug: blueprintSlug, occupantHandle: occupantHandle) },
            { resolveOccupantTitle(occupantHandle: occupantHandle, occupant: occupant) },
        ]
        for candidate in candidates {
            guard let resolved = candidate() else { continue }
            return resolved
        }

        let trimmedPlan = planTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedPlan.isEmpty ? trimmedPlan : "작업 방"
    }
}
