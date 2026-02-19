import Foundation

enum SupportedLocale: String, CaseIterable, Identifiable {
    case en
    case de
    case fr
    case es
    case it
    case pt
    case ko
    case ru
    case pl
    case zhHans = "zh_Hans"
    case zhHant = "zh_Hant"

    var id: String { rawValue }

    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .ko: return "한국어"
        case .ru: return "Русский"
        case .pl: return "Polski"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}
