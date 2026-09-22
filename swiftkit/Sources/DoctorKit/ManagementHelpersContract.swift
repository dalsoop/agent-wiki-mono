import Foundation

/// package-identity 가 helpers 인데 Contents/Helpers/<cli_product> 가 없거나 PATH 가 깨진 경우.
/// path-cli 는 비교 대상 Helpers 가 없으면 plain 을 ok 로 남겨 탐지 구멍이 생긴다.
///
/// Helpers 바이너리 이름 정본은 ADM 과 동일: `cli_product` → `cli` → `cli_helper_path` 파일명.
enum ManagementHelpersContract {
    static func findings(
        applicationsDirectory: String,
        pathRoots: [String],
        resolveOnPath: @Sendable (String, [String]) -> String?,
        isSymlink: @Sendable (String) -> Bool,
        readlink: @Sendable (String) -> String?,
        source: String
    ) -> [DoctorFinding] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: applicationsDirectory) else {
            return []
        }
        var out: [DoctorFinding] = []
        for name in names where name.hasSuffix(".app") {
            let appPath = (applicationsDirectory as NSString).appendingPathComponent(name)
            let identityPath = (appPath as NSString)
                .appendingPathComponent("Contents/Resources/package-identity.json")
            guard let data = fm.contents(atPath: identityPath),
                  let obj = DoctorJSON.object(from: data)
            else { continue }
            let dual = obj["dual_entry"] as? String ?? ""
            guard dual == "helpers" || dual == "cli-only" else { continue }
            let cli = (obj["cli"] as? String) ?? (obj["cli_product"] as? String) ?? ""
            guard !cli.isEmpty else { continue }
            let product = helpersProductName(from: obj) ?? cli
            let helper = (appPath as NSString)
                .appendingPathComponent("Contents/Helpers/\(product)")
            let helperOK = fm.fileExists(atPath: helper)
            let path = resolveOnPath(cli, pathRoots)
            if !helperOK {
                out.append(DoctorFinding(
                    category: .management,
                    severity: .fail,
                    body: .init(
                        subject: cli,
                        title: "helpers 계약 깨짐: Helpers/\(product) 없음 — \(name)",
                        detail: "package-identity dual_entry=\(dual) 인데 \(helper) 가 없다. "
                            + "옛 설치본이 Helpers product 없이 남은 상태. "
                            + "cli=\(cli) product=\(product) PATH=\(path ?? "없음")",
                        remedy: "app-build-manager ship 해당 앱 release "
                            + "(Helpers CLI product 재설치)"
                    ),
                    source: source,
                    payload: [
                        "cli": cli,
                        "cli_product": product,
                        "app": name,
                        "kind": "helpers_product_missing",
                        "dual_entry": dual,
                    ]
                ))
                continue
            }
            if let path {
                let linked = isSymlink(path)
                if linked, let target = readlink(path), !fm.fileExists(atPath: target) {
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .fail,
                        body: .init(
                            subject: cli,
                            title: "PATH broken symlink — \(cli)",
                            detail: "\(path) → \(target) (target missing). app=\(name)",
                            remedy: "rm \(path) && app-build-manager ship 해당 앱 release"
                        ),
                        source: source,
                        payload: [
                            "cli": cli,
                            "cli_product": product,
                            "app": name,
                            "kind": "broken_path_symlink",
                        ]
                    ))
                } else if !linked, dual == "helpers" {
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .warn,
                        body: .init(
                            subject: cli,
                            title: "PATH plain (Helpers 있는데 사본) — \(cli)",
                            detail: "\(path) 이 Helpers 심링크가 아니다. helper=\(helper)",
                            remedy: "path-cli-health repair-copies --apply  또는  "
                                + "rm \(path) && ln -s \(helper) \(path)"
                        ),
                        source: source,
                        payload: [
                            "cli": cli,
                            "cli_product": product,
                            "app": name,
                            "kind": "plain_despite_helper",
                        ]
                    ))
                }
            }
        }
        return out
    }

    /// ADM `helpersCLIContract` 과 같은 우선순위: cli_product → cli → cli_helper_path 파일명.
    static func helpersProductName(from identity: [String: Any]) -> String? {
        if let product = identity["cli_product"] as? String, !product.isEmpty {
            return product
        }
        if let cli = identity["cli"] as? String, !cli.isEmpty {
            return cli
        }
        if let helperPath = identity["cli_helper_path"] as? String, !helperPath.isEmpty {
            return (helperPath as NSString).lastPathComponent
        }
        return nil
    }
}
