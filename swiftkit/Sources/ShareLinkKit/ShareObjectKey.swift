import Foundation

/// 올릴 오브젝트의 키(경로)를 만든다.
///
/// 두 가지를 동시에 만족해야 한다:
/// - **겹치지 않는다** — 같은 초에 두 장을 올려도 서로를 덮어쓰면 안 된다.
/// - **추측되지 않는다** — 공유 링크는 대개 인증 없이 열린다. 날짜와 순번만 쓰면
///   남의 캡처 주소를 손으로 만들어 볼 수 있다.
public enum ShareObjectKey {

    /// 임의 부분의 길이. 22자면 충돌·추측 양쪽에 충분하다(62^22).
    public static let randomLength = 22

    /// 주소에 그대로 넣어도 안전한 글자만 쓴다 — 퍼센트 인코딩이 끼면 링크가 지저분해지고
    /// 일부 채팅앱이 주소 끝을 잘라 먹는다.
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// `<prefix>/<yyyy>/<MM>/<임의>.<ext>`
    ///
    /// 날짜 폴더를 두는 건 저장소를 사람이 열어 봤을 때 정리돼 보이게 하고,
    /// 수명주기 규칙(오래된 것 자동 삭제)을 걸기 쉬워서다.
    public static func make(
        prefix: String,
        fileExtension: String,
        date: Date,
        randomProvider: () -> String = { randomComponent() }
    ) -> String {
        var parts: [String] = []
        let cleanedPrefix = sanitize(prefix)
        if !cleanedPrefix.isEmpty { parts.append(cleanedPrefix) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month], from: date)
        parts.append(String(format: "%04d", components.year ?? 1970))
        parts.append(String(format: "%02d", components.month ?? 1))

        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let name = ext.isEmpty ? randomProvider() : "\(randomProvider()).\(ext.lowercased())"
        parts.append(name)
        return parts.joined(separator: "/")
    }

    public static func randomComponent(length: Int = randomLength) -> String {
        String((0..<max(1, length)).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    /// 접두사에서 앞뒤 슬래시·공백을 떼고, 주소에 넣기 곤란한 글자를 버린다.
    /// 사용자가 `/screenshots/` 처럼 적어도 그대로 동작해야 한다.
    static func sanitize(_ prefix: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_/"))
        let filtered = String(
            prefix.unicodeScalars.filter { allowed.contains($0) }.map(Character.init)
        )
        return filtered.split(separator: "/").joined(separator: "/")
    }
}
