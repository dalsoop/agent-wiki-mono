import Foundation

/// 앱의 사용자 노출 문자열 키. `CaseIterable` 이라 누락 검증 테스트가 전 키를 순회할 수 있다.
// 새 케이스를 추가하면 en.lproj / ko.lproj 의 Localizable.strings 에도 같은 키를 추가할 것.
enum L10nKey: String, CaseIterable {
    case menuRefresh = "menu.refresh"
    case menuSettings = "menu.settings"
    case menuQuit = "menu.quit"
    case settingsTitle = "settings.title"
    case settingsLanguage = "settings.language"
    case settingsLaunchAtLogin = "settings.launch_at_login"
    case CommandPromotionPrint = "CommandPromotion.print"
    case CommandPromotionPrint_2 = "CommandPromotion.print-2"
    case CommandTaskPrint = "CommandTask.print"
    case CommandTaskPrint_2 = "CommandTask.print-2"
    case CommandTaskPrint_3 = "CommandTask.print-3"
    case CommandRepositoryString = "CommandRepository.string"
    case CommandRepositoryString_2 = "CommandRepository.string-2"
    case mainString = "main.string"
    case mainString_2 = "main.string-2"
    case mainString_3 = "main.string-3"
    case mainString_4 = "main.string-4"
    case CommandWorldEmpty = "CommandWorld.empty"
    case CommandWorldAdded = "CommandWorld.added"
    case CommandSearchEmpty = "CommandSearch.empty"
    case CommandSearchUntitled = "CommandSearch.untitled"
    case CommandSearchSupport = "CommandSearch.support"
    case CommandSearchQuery = "CommandSearch.query"
    case CommandSearchWikiLayer = "CommandSearch.wikiLayer"
    case CommandSearchEvidenceLayer = "CommandSearch.evidenceLayer"
    case CommandSearchMore = "CommandSearch.more"
    case CommandSearchContradict = "CommandSearch.contradict"
}
