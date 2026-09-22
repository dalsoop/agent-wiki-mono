import Foundation

/// 패키지·소스 문자열에서 채택 사실을 읽는다.
///
/// `GujoManagedAdoption` 에 두면 파일 if/guard 와 타입 분기 합이 한도를 넘는다.
enum GujoManagedAdoptionText {
    /// `traits:` 배열 안에 `"GujoManaged"` 가 있나.
    ///
    /// 문자열이 주석이나 설명문에 나오는 것과 구분해야 해서 `traits:` 를 먼저 찾는다 —
    /// 단순 `contains("GujoManaged")` 는 이 파일을 설명하는 주석에도 걸린다.
    static func declaresTrait(_ package: String) -> Bool {
        var cursor = package.startIndex
        while let traits = package.range(of: "traits:", range: cursor..<package.endIndex) {
            guard let open = package.range(of: "[", range: traits.upperBound..<package.endIndex),
                  let close = package.range(of: "]", range: open.upperBound..<package.endIndex)
            else { return false }
            if package[open.upperBound..<close.lowerBound].contains("\"GujoManaged\"") {
                return true
            }
            cursor = close.upperBound
        }
        return false
    }

    /// Package.swift 가 LicenseKit product 를 **직접** 의존하는가.
    /// `code()` 는 문자열 내용을 지워서 product name 을 못 본다 — 줄 주석만 배제한다.
    static func declaresLicenseKitDependency(_ package: String) -> Bool {
        package.split(whereSeparator: \.isNewline).contains { raw in
            let s = String(raw)
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return false }
            if s.contains(".product(name: \"LicenseKit\"") { return true }
            return s.contains("name: \"LicenseKit\"") && s.contains("product")
        }
    }

    /// 앱 소스가 옛 키 활성화 경로를 **코드로** 쓰는가.
    static func sourceUsesLegacyLicenseAPI(in text: String) -> Bool {
        if mentions("import LicenseKit", in: text) { return true }
        for needle in ["activate(licenseKey", "LicenseManager(", "licenseKey:", "LicenseLinkView"] {
            if mentions(needle, in: text) { return true }
        }
        return false
    }

    /// 실행 제품이 있는 소비 앱인가. 라이브러리만 있는 패키지는 게이트 대상이 아니다.
    static func declaresExecutable(_ package: String) -> Bool {
        package.contains(".executable(") || package.contains(".executableTarget(")
    }

    /// SwiftUI `@main struct …: App` 창 진입. `AppModel` 오탐을 피한다.
    static func declaresSwiftUIApp(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            let code = code(in: String(line))
            guard code.contains("struct "), let r = code.range(of: ": App") else { return false }
            return isDeclarationTerminator(code[r.upperBound...].first)
        }
    }

    /// 함대 디렉터리 관례로 iOS/iPad 앱인가.
    /// `platforms:` 만 보면 macOS 스텁 컴파일용 `.macOS` 도 같이 선언돼 있어 구분 불가.
    static func isIOSFleetApp(directory: String) -> Bool {
        let d = directory.lowercased()
        if d.hasSuffix("-ios") || d.hasSuffix("ios") { return true }
        if d.contains("-ios-") || d.contains("ios-") { return true }
        if d.hasSuffix("-ipad") || d.contains("-ipad-") { return true }
        return false
    }

    /// `FleetManagedApp` / `FleetManagedMenuBarApp` 채택 — 스캐폴드가 게이트를 대신 건다.
    static func conformsToScaffold(_ text: String) -> Bool {
        ["FleetManagedApp", "FleetManagedMenuBarApp", "FleetManagedWindowGroupApp",
         "FleetManagedMenuBarWindowGroupApp", "FleetManagedMenuBarExtraApp",
         "RanodeApp", "RanodeMenuBarApp", "RanodeWindowGroupApp",
         "RanodeMenuBarWindowGroupApp", "RanodeMenuBarExtraApp"].contains { name in
            text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
                let code = code(in: String(line))
                guard code.contains("struct "), code.contains(": ") else { return false }
                // `: RanodeApp` · `: RanodeApp {` · `: RanodeMenuBarApp,` 만.
                // `RanodeAppBootstrap` 같은 접두 일치를 배제한다.
                guard let r = code.range(of: name) else { return false }
                return isDeclarationTerminator(code[r.upperBound...].first)
            }
        }
    }

    /// 소스에 **코드로서** 나오는가 — 주석과 문자열 리터럴 안은 안 센다.
    ///
    /// 실측(2026-08-05): 이 스캐너를 쓰는 콘솔 앱이 안내 문구에 `.gujoManaged()` 를
    /// 적었다는 이유로 **자기 자신을 managed 로 셌다**. grep 으로 교차검증했지만
    /// grep 도 같은 맹점이라 둘이 사이좋게 틀린 값에 합의했다 — 맹점을 공유하는
    /// 두 방법이 일치하는 건 검증이 아니다.
    static func mentions(_ needle: String, in text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { code(in: String($0)).contains(needle) }
    }

    /// 한 줄에서 주석과 문자열 리터럴 내용을 지운 나머지.
    ///
    /// 완전한 Swift 파서가 아니다 — 여러 줄 문자열·중첩 보간까지 다루지 않는다.
    /// 목적은 "설명문에 적힌 이름" 과 "실제 호출" 을 가르는 것뿐이고, 그 경계에서
    /// 틀리면 **덜 세는 쪽**(false negative)으로 틀린다. 채택률을 부풀리는 것보다 낫다.
    static func code(in line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "/", line.index(after: index) < line.endIndex,
                      line[line.index(after: index)] == "/" {
                break
            } else {
                out.append(ch)
            }
            index = line.index(after: index)
        }
        return out
    }

    /// LicenseKit 이 **본업**인 앱 — 키 원장·지갑·스토어·배포·키 활성화 제품.
    /// 이 앱들의 `import LicenseKit` 은 "옛 잔존" 이 아니라 제품 표면이다.
    static func isLicenseKitKeeper(directory: String) -> Bool {
        let d = directory.lowercased()
        if d.hasPrefix("license-") { return true }
        switch d {
        case "swift-app-store-swift",
             "app-build-manager-swift",
             "backup-duplicate-manager-swift",
             "gujo-account-manager-swift",
             "gujo-skill-store-swift":
            return true
        default:
            return false
        }
    }

    /// `struct …: Name` 뒤가 선언 끝인지 — `NameBootstrap` 접두 일치를 배제한다.
    static func isDeclarationTerminator(_ after: Character?) -> Bool {
        switch after {
        case nil, " ", ",", "\u{7B}": return true
        default: return false
        }
    }
}
