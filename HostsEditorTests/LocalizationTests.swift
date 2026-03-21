import Foundation
import Testing
@testable import HostsEditor

struct LocalizationTests {
    @Test
    func appLanguageResolvesSupportedIdentifiers() {
        #expect(AppLanguage.resolve("en") == .english)
        #expect(AppLanguage.resolve("en-US") == .english)
        #expect(AppLanguage.resolve("zh-Hans") == .simplifiedChinese)
        #expect(AppLanguage.resolve("zh-CN") == .simplifiedChinese)
        #expect(AppLanguage.resolve("zh-Hant") == .traditionalChinese)
        #expect(AppLanguage.resolve("zh-TW") == .traditionalChinese)
        #expect(AppLanguage.resolve("zh-HK") == .traditionalChinese)
    }

    @Test
    func appLanguageFallsBackFromPreferredLanguages() {
        #expect(AppLanguage.preferred(from: ["fr-FR", "zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.preferred(from: ["ja-JP", "zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.preferred(from: ["fr-FR", "de-DE"]) == .english)
    }

    @Test
    func localizationReturnsUpdatedStringsAfterLanguageSwitch() {
        let localization = AppLocalization(bundle: .main, initialLanguage: .simplifiedChinese)

        #expect(localization.string("menu.preferences") == "偏好设置…")

        localization.setLanguage(.english)

        #expect(localization.string("menu.preferences") == "Preferences…")
    }

    @MainActor
    @Test
    func updateStrategyTitlesFollowCurrentLanguage() {
        let originalLanguage = AppLocalization.shared.language
        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
        }

        AppLocalization.shared.setLanguage(.english)
        #expect(UpdateCheckStrategy.manual.title == "Manual")
        #expect(UpdateCheckStrategy.daily.title == "Daily")
        #expect(UpdateCheckStrategy.onLaunch.title == "On Launch")

        AppLocalization.shared.setLanguage(.traditionalChinese)
        #expect(UpdateCheckStrategy.manual.title == "手動檢查")
    }
}
