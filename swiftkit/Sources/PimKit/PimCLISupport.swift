import Foundation

/// PIM 스위트 CLI 공통기 — 날짜 인자 파싱과 상호운용 계약 봉투 출력.
/// 6개 CLI 가 같은 날짜 문법·같은 출력 규격을 쓰게 여기 한 곳에 둔다.
public enum PimCLI {
    /// CLI 날짜 인자 파서. 지원:
    ///   "2026-07-15" · "2026-07-15 14:00" · "today" · "tomorrow" · "+3d" · "+2h"
    public static func parseDate(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "today":
            return calendar.startOfDay(for: now)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        default:
            break
        }

        // 상대 오프셋: +3d / +2h / +30m
        if s.hasPrefix("+"), s.count >= 3, let value = Int(s.dropFirst().dropLast()) {
            switch s.last {
            case "d": return calendar.date(byAdding: .day, value: value, to: now)
            case "h": return calendar.date(byAdding: .hour, value: value, to: now)
            case "m": return calendar.date(byAdding: .minute, value: value, to: now)
            default: break
            }
        }

        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let fmt = DateFormatter()
            fmt.calendar = calendar
            fmt.timeZone = calendar.timeZone
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = format
            if let date = fmt.date(from: raw.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }

    /// 사람용 짧은 표기 (테이블 출력).
    public static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }

    /// 봉투(JSON) 출력 — 앱 상호운용 계약: {"ok":true,"result":...}.
    /// InteropKit.Envelope 와 같은 규격이되 PimKit 이 InteropKit 에 의존하지 않도록
    /// 인코딩만 여기서 재현한다(날짜는 vault 와 같은 ISO8601).
    private struct Success<R: Codable>: Codable {
        let ok: Bool
        let result: R
    }

    public static func printOK<T: Codable>(_ result: T) {
        let enc = PimVault.encoder()
        do {
            let data = try enc.encode(Success(ok: true, result: result))
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {}
    }

    /// `[String: Any]` 봉투. `printOK` 는 `Codable` 만 받는데 status 는 앱마다 키가
    /// 달라 사전이 자연스럽다 — 그 하나 때문에 앱마다 구조체를 만들지 않는다.
    public static func printOKDictionary(_ result: [String: Any]) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: ["ok": true, "result": result],
                options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            return
        }
    }

    public static func printFail(_ message: String) {
        struct Failure: Codable {
            struct Body: Codable { let message: String }
            let ok: Bool
            let error: Body
        }
        let enc = PimVault.encoder()
        do {
            let data = try enc.encode(Failure(ok: false, error: .init(message: message)))
            FileHandle.standardError.write(data + Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("{\"ok\":false,\"error\":{\"message\":\"encode failure\"}}\n".utf8))
        }
    }
}
