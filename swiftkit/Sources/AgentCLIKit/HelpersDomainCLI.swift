import StateRootKit
import DoctorContract
import Foundation
#if canImport(os)
import os
#elseif canImport(Synchronization)
import Synchronization
#endif
import InteropKit

/// dual-entry Helpers 스텁에 공통 도메인 동사 `status` / `doctor` 를 제공한다.
/// AppKit 없이 Foundation only — 전 앱 CLI 타깃이 AgentCLIKit 만 링크해도 쓸 수 있다.
///
/// - status: `~/.swift-app-state/<appKey>.json` 존재·mtime·원문 요약
/// - doctor: PATH CLI 실존 + registry 항목 + state 파일 힌트
public enum HelpersDomainCLI: Sendable {

    /// `status [--json]` — 상태 미러 읽기 (없으면 published=false).
    public static func status(appKey: String, json: Bool = false) -> Int32 {
        let path = StateRootKit.path(".swift-app-state/\(appKey).json")
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: path)
        var mtime = ""
        var bytes = 0
        var snippet = ""
        let attrs: [FileAttributeKey: Any]
        if exists {
            do {
                attrs = try fm.attributesOfItem(atPath: path)
            } catch {
                FileHandle.standardError.write(Data("status: attrs failed: \(error.localizedDescription)\n".utf8))
                attrs = [:]
            }
        } else {
            attrs = [:]
        }
        if !attrs.isEmpty {
            if let d = attrs[.modificationDate] as? Date {
                let f = ISO8601DateFormatter()
                mtime = f.string(from: d)
            }
            if let n = attrs[.size] as? NSNumber { bytes = n.intValue }
            if let data = fm.contents(atPath: path), let s = String(data: data, encoding: .utf8) {
                snippet = String(s.prefix(400))
            }
        }
        if json {
            let result: [String: Any] = [
                "appKey": appKey,
                "statePath": path,
                "published": exists,
                "mtime": mtime,
                "bytes": bytes,
                "snippet": snippet,
            ]
            emitJSON(["ok": true, "result": result])
            return 0
        }
        if !exists {
            print("status appKey=\(appKey) published=false path=\(path)")  // allow:debug — CLI human-readable status/doctor stdout
            print("(GUI/데몬이 StateMirror 를 아직 안 올렸거나 키 이름이 다를 수 있음)")  // allow:debug — CLI human-readable status/doctor stdout
            return 0
        }
        print("status appKey=\(appKey) published=true mtime=\(mtime) bytes=\(bytes)")  // allow:debug — CLI human-readable status/doctor stdout
        print("path=\(path)")  // allow:debug — CLI human-readable status/doctor stdout
        if !snippet.isEmpty { print(snippet) }  // allow:debug — CLI human-readable status/doctor stdout
        return 0
    }

    /// `doctor [--json]` — CLI 바이너리·registry·state 힌트.
    /// 배관 사실만 모아 돌려준다 — **찍지 않는다.**
    ///
    /// 앱이 자기 도메인 점검을 doctor 에 얹을 때, 배관이 자기 JSON 봉투를 먼저 찍어 버리면
    /// `--json` 출력이 봉투 두 개가 되어 소비자가 파싱하지 못한다(실측 2026-08-11:
    /// sparkle-update-studio doctor). 찍는 것과 재는 것을 나눈다.
    public static func doctorFacts(
        cliName: String,
        appKey: String? = nil,
        extra: [any DoctorProvider] = []
    )
        -> (facts: [String: Any], ok: Bool)
    {
        let key = appKey ?? cliName
        let home = NSHomeDirectory()
        let candidates = [
            HostPlatform.cliBinPath(cliName),
            "/usr/local/bin/\(cliName)",
            (home as NSString).appendingPathComponent(".local/bin/\(cliName)"),
        ]
        let bin = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        // 레지스트리 읽기는 소유 SSOT(InteropKit RegistryStore)로 — 경로 직접 조립 금지.
        let matched = ((try? RegistryStore().load())?.apps ?? [:])
            .first { name, caps in
                let base = (caps.cli as NSString).lastPathComponent
                return base == cliName || name == cliName || caps.name == cliName
            }
        let inRegistry = matched != nil
        let regName = matched?.key ?? ""
        let statePath = StateRootKit.path(".swift-app-state/\(key).json")
        let stateOK = FileManager.default.fileExists(atPath: statePath)
        // 공용 provider 결과도 같이 싣는다 — 자기 도메인 doctor 를 쓰는 앱이
        // 공용 검사를 잃으면 "앱마다 다른 것만 보는" 상태로 되돌아간다.
        let findings = runBlocking {
            await AppSelfDoctor.scan(cliName: cliName, appKey: key, extra: extra).findings
        }
        let ok = bin != nil && !findings.contains { $0.severity == .fail }
        return ([
            "findings": findings.map {
                [
                    "severity": $0.severity.rawValue, "category": $0.category.rawValue,
                    "title": $0.title, "detail": $0.detail,
                    "remedy": $0.remedy ?? "", "source": $0.source,
                ]
            },
            "cliName": cliName,
            "binary": bin ?? "",
            "binaryOK": bin != nil,
            "registry": inRegistry,
            "registryName": regName,
            "statePath": statePath,
            "statePublished": stateOK,
            "ok": ok,
        ], ok)
    }

    /// 배관 사실을 사람이 읽게 찍는다(도메인 점검을 덧붙이는 앱이 재사용).
    public static func printDoctorFacts(_ facts: [String: Any]) {
        let cliName = facts["cliName"] as? String ?? "?"
        let bin = facts["binary"] as? String ?? ""
        let inRegistry = facts["registry"] as? Bool ?? false
        let regName = facts["registryName"] as? String ?? ""
        let statePath = facts["statePath"] as? String ?? ""
        let stateOK = facts["statePublished"] as? Bool ?? false
        print("doctor cli=\(cliName)")  // allow:debug — CLI human-readable status/doctor stdout
        print("  binary: \(bin.isEmpty ? "(missing)" : bin) \(bin.isEmpty ? "FAIL" : "OK")")  // allow:debug — CLI human-readable status/doctor stdout
        print("  registry: \(inRegistry ? "yes (\(regName))" : "no")")  // allow:debug — CLI human-readable status/doctor stdout
        print("  state: \(stateOK ? statePath : "(none) \(statePath)")")  // allow:debug — CLI human-readable status/doctor stdout
        for finding in (facts["findings"] as? [[String: String]]) ?? [] {
            print("  [\(finding["severity"] ?? "")] \(finding["title"] ?? "") — \(finding["detail"] ?? "")")  // allow:debug — CLI human-readable status/doctor stdout
            if let remedy = finding["remedy"], !remedy.isEmpty {
                print("      → \(remedy)")  // allow:debug — CLI human-readable status/doctor stdout
            }
        }
    }

    /// **동기로 유지한다.** 112개 앱의 `main.swift` 가 top-level 에서 부르는데,
    /// async 로 바꾸면 그 파일들이 async 컨텍스트가 되어 dual-entry 가 멈춘다
    /// (2026-07-25 실측). 비동기 provider 는 안에서 세마포어로 감싼다.
    public static func doctor(
        cliName: String,
        appKey: String? = nil,
        json: Bool = false,
        extra: [any DoctorProvider] = []
    ) -> Int32 {
        let key = appKey ?? cliName
        let home = NSHomeDirectory()
        let candidates = [
            HostPlatform.cliBinPath(cliName),
            "/usr/local/bin/\(cliName)",
            (home as NSString).appendingPathComponent(".local/bin/\(cliName)"),
        ]
        let bin = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        // 레지스트리 읽기는 소유 SSOT(InteropKit RegistryStore)로 — 경로 직접 조립 금지.
        let matched = ((try? RegistryStore().load())?.apps ?? [:])
            .first { name, caps in
                let base = (caps.cli as NSString).lastPathComponent
                return base == cliName || name == cliName || caps.name == cliName
            }
        let inRegistry = matched != nil
        let regName = matched?.key ?? ""
        let statePath = StateRootKit.path(".swift-app-state/\(key).json")
        let stateOK = FileManager.default.fileExists(atPath: statePath)
        // 진단은 **provider 가 만든다.** 여기에 if 를 더하면 이 함수가 쓰레기통이 되고,
        // 오늘처럼 검사가 여섯 갈래로 흩어진다. 룰은 AppSelfDoctor 에 꽂는다.
        let findings = runBlocking {
            await AppSelfDoctor.scan(cliName: cliName, appKey: key, extra: extra).findings
        }
        let failures = findings.filter { $0.severity == .fail }
        let ok = bin != nil && failures.isEmpty
        if json {
            let result: [String: Any] = [
                "cliName": cliName,
                "binary": bin ?? "",
                "binaryOK": bin != nil,
                "registry": inRegistry,
                "registryName": regName,
                "statePath": statePath,
                "statePublished": stateOK,
                // 공용 스키마 그대로 싣는다 — 앱마다 다른 모양이면 함대 집계가 안 된다.
                "findings": findings.map {
                    [
                        "severity": $0.severity.rawValue, "category": $0.category.rawValue,
                        "title": $0.title, "detail": $0.detail,
                        "remedy": $0.remedy ?? "", "source": $0.source,
                    ]
                },
                "ok": ok,
            ]
            emitJSON(["ok": true, "result": result])
            return ok ? 0 : 1
        }
        print("doctor cli=\(cliName)")  // allow:debug — CLI human-readable status/doctor stdout
        print("  binary: \(bin ?? "(missing)") \(bin != nil ? "OK" : "FAIL")")  // allow:debug — CLI human-readable status/doctor stdout
        print("  registry: \(inRegistry ? "yes (\(regName))" : "no")")  // allow:debug — CLI human-readable status/doctor stdout
        print("  state: \(stateOK ? statePath : "(none) \(statePath)")")  // allow:debug — CLI human-readable status/doctor stdout
        for finding in findings {
            print("  [\(finding.severity.rawValue)] \(finding.title) — \(finding.detail)")  // allow:debug — CLI human-readable status/doctor stdout
            if let remedy = finding.remedy, !remedy.isEmpty {
                print("      → \(remedy)")  // allow:debug — CLI human-readable status/doctor stdout
            }
        }
        return ok ? 0 : 1
    }

    /// 비동기 provider 를 동기 진입점에서 돌린다.
    static func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }

    /// 비동기 결과를 건네받을 상자. 제네릭 함수 안에는 타입을 못 넣어 바깥에 둔다.
    /// lock 자체가 Sendable 이라 detached 클로저에서 안전하게 캡처된다.
    final class ResultBox<V: Sendable>: Sendable {
        #if canImport(os)
        private let state = OSAllocatedUnfairLock<V?>(initialState: nil)
        var value: V? {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
        #elseif canImport(Synchronization)
        private let state = Mutex<V?>(nil)
        var value: V? {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
        #endif
    }

    /// `--json` 플래그 추출 + unknown option 거절.
    public static func parseJSONFlag(_ rest: ArraySlice<String>) -> (json: Bool, error: String?) {
        var json = false
        for a in rest {
            switch a {
            case "--json":
                json = true
            case let opt where opt.hasPrefix("-"):
                return (false, "알 수 없는 옵션: \(opt) (허용: --json)")
            default:
                return (false, "알 수 없는 인자: \(a)")
            }
        }
        return (json, nil)
    }

    private static func emitJSON(_ obj: [String: Any]) {
        let text: String
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            text = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            FileHandle.standardError.write(Data("error: json encode: \(error.localizedDescription)\n".utf8))
            return
        }
        print(text)  // allow:debug — CLI human-readable status/doctor stdout
    }
}
