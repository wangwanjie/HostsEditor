import Foundation
import Testing
@testable import HostsEditor

struct HostsManagerDatabaseTests {
    @MainActor
    @Test
    func appSettingsLoadsPersistedValuesFromDatabase() throws {
        let database = try AppDatabase.inMemory()
        try database.saveSetting(.appLanguage, value: .string(AppLanguage.english.rawValue))
        try database.saveSetting(.appAppearance, value: .string(AppAppearance.dark.rawValue))
        try database.saveSetting(.updateCheckStrategy, value: .string(UpdateCheckStrategy.onLaunch.rawValue))
        try database.saveSetting(.editorFontSize, value: .double(18))
        try database.saveSetting(.sidebarWidth, value: .double(260))

        let settings = AppSettings(database: database)

        #expect(settings.appLanguage == .english)
        #expect(settings.appAppearance == .dark)
        #expect(settings.updateCheckStrategy == .onLaunch)
        #expect(settings.editorFontSize == 18)
        #expect(settings.sidebarWidth == 260)
    }

    @MainActor
    @Test
    func hostsManagerLoadsProfilesAndBaseContentFromDatabase() throws {
        let database = try AppDatabase.inMemory()
        let profiles = [
            HostsProfile(id: "local", name: "Local", content: "127.0.0.1 local.test"),
            HostsProfile(id: "remote", name: "Remote", content: "127.0.0.1 remote.test", isEnabled: true, isRemote: true, remoteURL: "https://example.test/hosts", lastUpdated: Date(timeIntervalSince1970: 1_744_000_000)),
        ]
        try database.saveProfiles(profiles)
        try database.saveSetting(.baseSystemContent, value: .string("127.0.0.1 localhost"))

        let manager = HostsManager(database: database)

        #expect(manager.profiles == profiles)
        #expect(manager.baseSystemContent == "127.0.0.1 localhost")
    }
}
