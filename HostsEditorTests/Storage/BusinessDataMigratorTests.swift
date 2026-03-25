import Foundation
import Testing
@testable import HostsEditor

@Suite(.serialized)
struct BusinessDataMigratorTests {
    @Test
    func migratorCopiesLegacyBusinessValuesAndClearsLegacyKeys() throws {
        let suiteName = "HostsEditorTests.BusinessDataMigratorTests.copy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = HostsProfile(
            id: "migrated-profile",
            name: "Migrated",
            content: "127.0.0.1 migrated.test",
            isEnabled: true,
            isRemote: true,
            remoteURL: "https://example.test/hosts",
            lastUpdated: Date(timeIntervalSince1970: 1_744_000_000)
        )
        defaults.set(try JSONEncoder().encode([profile]), forKey: "HostsEditorProfiles")
        defaults.set("127.0.0.1 localhost", forKey: "HostsEditorBaseContent")
        defaults.set("daily", forKey: "HostsEditorUpdateCheckStrategy")
        defaults.set("english", forKey: "HostsEditorAppLanguage")
        defaults.set("dark", forKey: "HostsEditorAppAppearance")
        defaults.set(15.0, forKey: "HostsEditorEditorFontSize")
        defaults.set(300.0, forKey: "HostsEditorSidebarWidth")
        defaults.set(true, forKey: "HostsEditorRuntimeUnrelated")

        let database = try AppDatabase.inMemory()
        try BusinessDataMigrator(defaults: defaults, database: database).migrateIfNeeded()

        #expect(try database.loadProfiles() == [profile])
        #expect(try database.settingValue(.baseSystemContent) == .string("127.0.0.1 localhost"))
        #expect(try database.settingValue(.updateCheckStrategy) == .string("daily"))
        #expect(try database.settingValue(.appLanguage) == .string("english"))
        #expect(try database.settingValue(.appAppearance) == .string("dark"))
        #expect(try database.settingValue(.editorFontSize) == .double(15.0))
        #expect(try database.settingValue(.sidebarWidth) == .double(300.0))

        #expect(defaults.object(forKey: "HostsEditorProfiles") == nil)
        #expect(defaults.object(forKey: "HostsEditorBaseContent") == nil)
        #expect(defaults.object(forKey: "HostsEditorUpdateCheckStrategy") == nil)
        #expect(defaults.object(forKey: "HostsEditorAppLanguage") == nil)
        #expect(defaults.object(forKey: "HostsEditorAppAppearance") == nil)
        #expect(defaults.object(forKey: "HostsEditorEditorFontSize") == nil)
        #expect(defaults.object(forKey: "HostsEditorSidebarWidth") == nil)
        #expect(defaults.bool(forKey: "HostsEditorRuntimeUnrelated"))
    }

    @Test
    func migratorLeavesLegacyKeysIntactWhenVerificationFails() throws {
        let suiteName = "HostsEditorTests.BusinessDataMigratorTests.failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try JSONEncoder().encode([HostsProfile(id: "kept", name: "Kept", content: "127.0.0.1 kept.test")]), forKey: "HostsEditorProfiles")
        defaults.set("127.0.0.1 keep", forKey: "HostsEditorBaseContent")

        let database = try AppDatabase.inMemory()
        let migrator = BusinessDataMigrator(defaults: defaults, database: database) { _, _ in
            false
        }

        do {
            try migrator.migrateIfNeeded()
            Issue.record("Expected verification to fail")
        } catch BusinessDataMigrator.MigrationError.verificationFailed {
            // Expected failure.
        }

        #expect(defaults.object(forKey: "HostsEditorProfiles") != nil)
        #expect(defaults.object(forKey: "HostsEditorBaseContent") != nil)
    }

    @Test
    func migratorSupportsFileBackedDatabaseReopen() throws {
        let suiteName = "HostsEditorTests.BusinessDataMigratorTests.file.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BusinessDataMigratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databasePath = tempDirectory.appendingPathComponent("hosts_editor.sqlite").path
        defaults.set(try JSONEncoder().encode([HostsProfile(id: "persisted", name: "Persisted", content: "127.0.0.1 persisted.test")]), forKey: "HostsEditorProfiles")
        defaults.set("onLaunch", forKey: "HostsEditorUpdateCheckStrategy")

        let firstOpen = try AppDatabase(configuration: AppDatabaseConfiguration(databasePath: databasePath))
        try BusinessDataMigrator(defaults: defaults, database: firstOpen).migrateIfNeeded()

        let reopened = try AppDatabase(configuration: AppDatabaseConfiguration(databasePath: databasePath))
        #expect(try reopened.loadProfiles() == [HostsProfile(id: "persisted", name: "Persisted", content: "127.0.0.1 persisted.test")])
        #expect(try reopened.settingValue(.updateCheckStrategy) == .string("onLaunch"))
        #expect(defaults.object(forKey: "HostsEditorProfiles") == nil)
        #expect(defaults.object(forKey: "HostsEditorUpdateCheckStrategy") == nil)
    }
}
