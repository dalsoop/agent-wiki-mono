import Foundation

/// 1회성 마이그레이션 도우미(계약 §4). 킷의 다른 어떤 경로도 env 를 읽지 않는다 — 이 함수만
/// env·파일에 남아 있는 옛 토큰을 찾아 Keychain 으로 옮기고, 지워야 할 파일을 **안내**한다
/// (파일 삭제는 사용자 환경 변경이라 킷이 하지 않는다).
public struct LegacyImportReport: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case environment(String)
        case file(URL)

        public var label: String {
            switch self {
            case .environment(let name): return "env \(name)"
            case .file(let url): return url.path
            }
        }
    }

    /// Keychain 에 들어간 세션의 출처(`gst_` 토큰이 검증된 경우).
    public var imported: Source?
    /// `gst_` 가 아닌 옛 토큰(ops/intake/skill 등). 스태프 세션이 될 수 없어 재로그인이 필요하다.
    public var unsupported: [Source]
    /// 검증(`/api/staff/me`)에 실패한 `gst_` 토큰 출처.
    public var rejected: [Source]
    /// 사용자가 손으로 지워야 할 파일. 킷은 지우지 않는다.
    public var filesToDelete: [URL]

    public init(
        imported: Source? = nil, unsupported: [Source] = [], rejected: [Source] = [],
        filesToDelete: [URL] = []
    ) {
        self.imported = imported
        self.unsupported = unsupported
        self.rejected = rejected
        self.filesToDelete = filesToDelete
    }

    /// 앱 안 프롬프트에 그대로 띄울 안내문.
    public var guidance: String {
        var lines: [String] = []
        if let imported {
            lines.append("스태프 토큰을 \(imported.label) 에서 Keychain(net.ranode.gujo/staff) 으로 옮겼습니다.")
        } else {
            lines.append("옮길 스태프 토큰(gst_)이 없습니다. 앱에서 스태프 로그인을 진행하세요.")
        }
        if !unsupported.isEmpty {
            lines.append("옛 형식 토큰은 스태프 세션이 될 수 없습니다: "
                + unsupported.map(\.label).joined(separator: ", ") + ". 로그인으로 교체하세요.")
        }
        if !rejected.isEmpty {
            lines.append("서버가 거부한 토큰: " + rejected.map(\.label).joined(separator: ", "))
        }
        if !filesToDelete.isEmpty {
            lines.append("다음 파일은 더 이상 읽지 않으니 지우세요: "
                + filesToDelete.map(\.path).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

extension GujoStaffAuth {
    /// 옛 토큰이 살던 env 이름(우선순위 순). `gst_` 접두사만 스태프 세션으로 받는다.
    public static let legacyEnvironmentNames = [
        "GUJO_STAFF_TOKEN", "GUJO_OPS_TOKEN", "GUJO_INTAKE_TOKEN", "GUJO_SKILL_STORE_TOKEN",
    ]

    /// 옛 토큰 파일 후보(홈 기준 상대 경로).
    public static let legacyFileRelativePaths = [
        ".gujo/staff-token", ".gujo/ops-token", ".gujo/intake-token", ".gujo/skill-store-token",
    ]

    /// env/파일 → Keychain 1회 이관. 첫 번째로 검증에 성공한 `gst_` 토큰 하나만 저장한다.
    public func importLegacy(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) async -> LegacyImportReport {
        var report = LegacyImportReport()
        let candidates = Self.legacyCandidates(environment: environment, homeDirectory: homeDirectory)
        report.filesToDelete = candidates.compactMap(\.fileURL)
        for candidate in candidates {
            guard candidate.value.hasPrefix("gst_") else {
                report.unsupported.append(candidate.source)
                continue
            }
            guard report.imported == nil else { continue }
            do {
                adopt(try await me(token: candidate.value))
                report.imported = candidate.source
            } catch {
                report.rejected.append(candidate.source)
            }
        }
        return report
    }

    struct LegacyCandidate: Equatable {
        let source: LegacyImportReport.Source
        let value: String

        var fileURL: URL? {
            if case .file(let url) = source { return url }
            return nil
        }
    }

    static func legacyCandidates(
        environment: [String: String], homeDirectory: String
    ) -> [LegacyCandidate] {
        var out: [LegacyCandidate] = []
        for name in legacyEnvironmentNames {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                out.append(LegacyCandidate(source: .environment(name), value: value))
            }
        }
        let home = URL(fileURLWithPath: homeDirectory)
        for relative in legacyFileRelativePaths {
            let url = home.appendingPathComponent(relative)
            guard let data = FileManager.default.contents(atPath: url.path),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                out.append(LegacyCandidate(source: .file(url), value: value))
            }
        }
        return out
    }
}
