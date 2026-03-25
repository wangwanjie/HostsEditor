import AppKit
import Foundation
import Testing
@testable import HostsEditor

@Suite(.serialized)
struct AppSettingsLocalizationTests {
    @MainActor
    @Test
    func appSettingsPersistsLanguageAndAppearanceAndAppliesThem() throws {
        let database = try AppDatabase.inMemory()

        let application = NSApplication.shared
        let originalAppearance = application.appearance
        let originalLanguage = AppLocalization.shared.language

        defer {
            application.appearance = originalAppearance
            AppLocalization.shared.setLanguage(originalLanguage)
        }

        let settings = AppSettings(database: database)

        settings.appLanguage = .english
        settings.appAppearance = .dark

        #expect(try database.settingValue(.appLanguage) == .string(AppLanguage.english.rawValue))
        #expect(try database.settingValue(.appAppearance) == .string(AppAppearance.dark.rawValue))
        #expect(AppLocalization.shared.language == .english)
        #expect(application.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
