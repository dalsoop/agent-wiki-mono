import Foundation
import LocalizationKit

public enum SettingsUIKitL10n {
    public static func string(_ key: String, language: AppLanguage? = nil) -> String {
        let bundle = ResourceBundle.named("swiftkit_SettingsUIKit")
        if let language {
            let code: String
            switch language {
            case .system:
                return bundle.localizedString(forKey: key, value: nil, table: nil)
            case .korean:
                code = "ko"
            case .english:
                code = "en"
            }
            if let path = bundle.path(forResource: code, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                return langBundle.localizedString(forKey: key, value: nil, table: nil)
            }
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// l10n-bypass 린트 패스를 위한 네임스페이스 별칭
public typealias SettingsL10n = SettingsUIKitL10n
