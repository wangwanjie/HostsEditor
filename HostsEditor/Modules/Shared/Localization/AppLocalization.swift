import Combine
import Foundation

final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    @Published private(set) var language: AppLanguage

    var locale: Locale {
        language.locale
    }

    private let baseBundle: Bundle

    init(bundle: Bundle = .main, initialLanguage: AppLanguage = .simplifiedChinese) {
        self.baseBundle = bundle
        self.language = initialLanguage
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
    }

    func string(_ key: String, _ arguments: CVarArg..., table: String = "Localizable") -> String {
        string(key, arguments: arguments, table: table)
    }

    func string(_ key: String, arguments: [CVarArg], table: String = "Localizable") -> String {
        let format = localizedBundle.localizedString(forKey: key, value: nil, table: table)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var localizedBundle: Bundle {
        guard let path = baseBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return baseBundle
        }
        return bundle
    }
}
