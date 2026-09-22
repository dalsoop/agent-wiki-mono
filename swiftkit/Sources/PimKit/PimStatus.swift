import Foundation

/// PIM 앱들의 `status` — **한 번 쓰고 일곱이 부른다.**
///
/// 관측 계약(`InteropKit.ObservabilityContract`)이 요구하는 표준 질문이다. 일곱 앱에
/// 손으로 각각 쓰면 모양이 갈리고, 갈리면 함대가 조합할 때 또 앱마다 파서를 둬야 한다.
/// PIM 은 **같은 볼트(`~/PimVault`)를 공유**하므로 답의 뼈대도 공유할 수 있다.
///
/// 각 앱은 자기 항목 수만 넘긴다. 볼트 위치·존재 여부는 여기가 채운다 —
/// 그게 "왜 0건인가" 를 가르는 값이기 때문이다. 볼트가 아예 없는 것과 비어 있는 것은
/// 다른 상황인데, 항목 수만 내면 둘 다 0 으로 보인다.
public enum PimStatus {
    /// - Parameters:
    ///   - vault: 대상 볼트.
    ///   - file: 이 앱이 읽는 파일(그 앱의 정본). 없으면 볼트 루트만 본다.
    ///   - counts: 앱이 세어 넘긴 항목 수(예: `["todos": 12, "done": 5]`).
    public static func payload(vault: PimVault,
                               file: URL? = nil,
                               counts: [String: Int]) -> [String: Any] {
        let fm = FileManager.default
        var result: [String: Any] = [
            "vault": vault.root.path,
            "vaultExists": fm.fileExists(atPath: vault.root.path),
        ]
        if let file {
            result["file"] = file.path
            // 파일이 없는 것은 **고장이 아니다** — 아직 아무것도 안 담은 상태다.
            result["fileExists"] = fm.fileExists(atPath: file.path)
        }
        for (key, value) in counts { result[key] = value }
        return result
    }

    /// 사람이 읽는 한 줄들. JSON 과 **같은 값**을 낸다 — 갈리면 둘 중 하나가 거짓말한다.
    public static func lines(vault: PimVault,
                             file: URL? = nil,
                             counts: [(label: String, value: Int)]) -> [String] {
        let fm = FileManager.default
        var out = [counts.map { "\($0.label) \($0.value)" }.joined(separator: " · ")]
        if let file, !fm.fileExists(atPath: file.path) {
            out.append("(아직 파일 없음 — 담으면 생긴다: \(file.path))")
        } else {
            out.append("볼트: \(vault.root.path)")
        }
        return out
    }
}
