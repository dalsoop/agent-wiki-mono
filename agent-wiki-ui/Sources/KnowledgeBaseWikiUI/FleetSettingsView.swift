import KnowledgeBaseWikiCore
import SwiftUI

/// Settings → Fleet 탭 — multi-world 관제 평면(정본 아님) 요약.
/// CLI `fleet list|doctor` 와 같은 Core 를 읽고, 에이전트/운영자가 GUI 에서도 상태를 본다.
struct FleetSettingsView: View {
    @State private var registry: FleetRegistry = FleetRegistry()
    @State private var report: FleetDoctorReport?
    @State private var loadError: String?
    @State private var busy = false
    @State private var message: String?

    private var cliInstalled: String {
        DualEntry.installedCLIVersion(expected: LedgerVersion.current, allowProcessProbe: true)
    }

    var body: some View {
        Form {
            Section("버전") {
                LabeledContent("앱 (LedgerVersion)", value: LedgerVersion.current)
                LabeledContent("PATH CLI", value: cliInstalled.isEmpty ? "(미검출)" : cliInstalled)
                    .foregroundStyle(cliInstalled == LedgerVersion.current ? .primary : Color.orange)
                if cliInstalled != LedgerVersion.current {
                    Text("CLI 가 앱보다 오래됐거나 따로 설치돼 있습니다. \(LedgerModel.cliPathGuidance)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Fleet 레지스트리") {
                LabeledContent("경로", value: FleetStore().fileURL.path)
                LabeledContent("등록 world", value: "\(registry.worlds.count)개")
                if registry.workspaceRoots.isEmpty {
                    LabeledContent("workspaceRoots", value: "(없음)")
                } else {
                    ForEach(registry.workspaceRoots, id: \.self) { root in
                        Text(root).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if let loadError {
                    Text(loadError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Worlds") {
                let worlds = registry.worlds.sorted { $0.name < $1.name }
                if worlds.isEmpty {
                    Text("비어 있음 — `fleet scan --apply` 또는 아래 새로고침 후 등록.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(worlds, id: \.name) { (w: FleetWorldEntry) in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(w.enabled ? "●" : "○").foregroundStyle(w.enabled ? .green : .secondary)
                                Text(w.name).font(.body.weight(.medium))
                                Spacer()
                                Text(String(format: "w=%.2g", w.defaultWeight))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(w.kind.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(w.rootPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                            if let h = report?.worlds.first(where: { $0.name == w.name }) {
                                Text(healthLine(h))
                                    .font(.caption2)
                                    .foregroundStyle(h.exists && h.hasObjectsDir ? Color.secondary : Color.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let report, !report.issues.isEmpty {
                Section("Doctor (\(report.issues.count))") {
                    ForEach(report.issues, id: \.id) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Text(severityMark(issue.severity))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(severityColor(issue.severity))
                                .frame(width: 36, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.message).font(.caption)
                                if let world = issue.world {
                                    Text(world).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("동작") {
                Button(busy ? "검사 중…" : "Fleet doctor 새로고침") {
                    reload()
                }
                .disabled(busy)
                Button("config world 를 fleet 에 등록 (존재하는 경로만)") {
                    registerConfigWorlds()
                }
                .disabled(busy)
                Button("fleet.json Finder 에서 열기") {
                    NSWorkspace.shared.activateFileViewerSelecting([FleetStore().fileURL])
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("검색: `knowledge-base-wiki search <q> --fleet` · pull/weight 는 CLI. 정본은 각 world 원장, fleet 는 관제 맵만.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear { reload() }
    }

    private func healthLine(_ h: FleetWorldHealth) -> String {
        var parts: [String] = []
        parts.append(h.exists ? "경로 OK" : "경로 없음")
        if h.hasObjectsDir {
            if let n = h.objectFileCount { parts.append("objects≈\(n)") }
            else { parts.append("objects/") }
        } else {
            parts.append("objects 없음")
        }
        if !h.absolutePath { parts.append("상대경로") }
        return parts.joined(separator: " · ")
    }

    private func severityMark(_ s: FleetIssueSeverity) -> String {
        switch s {
        case .error: return "error"
        case .warning: return "warn"
        case .info: return "info"
        }
    }

    private func severityColor(_ s: FleetIssueSeverity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func reload() {
        busy = true
        loadError = nil
        message = nil
        defer { busy = false }
        do {
            let reg = try FleetStore().load()
            registry = reg
            report = FleetDiagnostics.doctor(registry: reg)
        } catch {
            loadError = "\(error)"
            registry = FleetRegistry()
            report = nil
        }
    }

    /// LedgerConfig 에만 있고 fleet 에 없는 world 를 등록(경로 실존 시).
    private func registerConfigWorlds() {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let store = FleetStore()
            var reg = try store.load()
            let config = LedgerConfig.load()
            var added = 0
            for lw in config.effectiveWorlds {
                let path = (lw.rootPath as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let already = reg.worlds.contains { $0.name == lw.name || $0.rootPath == path }
                guard !already else { continue }
                let kind: FleetWorldKind = path.contains(".wiki") ? .repo : .personal
                reg = try store.register(
                    name: lw.name, rootPath: path, kind: kind, defaultWeight: kind == .personal ? 0.5 : 1.0)
                added += 1
            }
            registry = reg
            report = FleetDiagnostics.doctor(registry: reg)
            message = added == 0 ? "추가할 config world 없음" : "\(added)개 world 등록"
        } catch {
            message = "등록 실패: \(error)"
        }
    }
}
