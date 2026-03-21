import AppKit
import Foundation
import Testing
@testable import HostsEditor

@Suite(.serialized)
struct AppSettingsLocalizationTests {
    @MainActor
    @Test
    func appSettingsPersistsLanguageAndAppearanceAndAppliesThem() {
        let suiteName = "HostsEditorTests.AppSettingsLocalizationTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let application = NSApplication.shared
        let originalAppearance = application.appearance
        let originalLanguage = AppLocalization.shared.language

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            application.appearance = originalAppearance
            AppLocalization.shared.setLanguage(originalLanguage)
        }

        let settings = AppSettings(defaults: defaults)

        settings.appLanguage = .english
        settings.appAppearance = .dark

        #expect(defaults.string(forKey: "HostsEditorAppLanguage") == AppLanguage.english.rawValue)
        #expect(defaults.string(forKey: "HostsEditorAppAppearance") == AppAppearance.dark.rawValue)
        #expect(AppLocalization.shared.language == .english)
        #expect(application.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
