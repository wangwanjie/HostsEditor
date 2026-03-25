import Foundation
import GRDB
import Testing
@testable import HostsEditor

struct AppDatabaseTests {
    @Test
    func databaseCreatesSchemaAndRoundTripsSettings() throws {
        let database = try AppDatabase.inMemory()

        try database.write { db in
            try database.saveSetting(.appLanguage, value: .string("en"), db: db)
        }

        let value = try database.read { db in
            try database.settingValue(.appLanguage, db: db)
        }

        #expect(value == .string("en"))
    }

    @Test
    func databaseRoundTripsProfiles() throws {
        let database = try AppDatabase.inMemory()
        let updatedAt = Date(timeIntervalSince1970: 1_744_000_000)
        let profile = HostsProfile(
            name: "Remote",
            content: "127.0.0.1 remote.example.test",
            isEnabled: true,
            isRemote: true,
            remoteURL: "https://example.test/hosts",
            lastUpdated: updatedAt
        )

        try database.saveProfiles([profile])

        let reloaded = try database.loadProfiles()
        #expect(reloaded == [profile])
    }

    @Test
    func databaseConvenienceSettingHelpersRoundTrip() throws {
        let database = try AppDatabase.inMemory()

        try database.saveSetting(.sidebarWidth, value: .double(280))

        let value = try database.settingValue(.sidebarWidth)
        #expect(value == .double(280))
    }

    @Test
    func databaseSchemaIncludesProfileOrderColumn() throws {
        let database = try AppDatabase.inMemory()

        let columnNames = try database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(profiles)").map { row in
                row["name"] as String
            }
        }

        #expect(columnNames.contains("sort_index"))
    }

    @Test
    func databasePreservesProfileOrder() throws {
        let database = try AppDatabase.inMemory()
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_744_000_500)
        let first = HostsProfile(
            id: "profile-second",
            name: "Second",
            content: "127.0.0.1 second.example.test",
            isEnabled: true,
            isRemote: true,
            remoteURL: "https://example.test/second",
            lastUpdated: remoteUpdatedAt
        )
        let second = HostsProfile(
            id: "profile-first",
            name: "First",
            content: "127.0.0.1 first.example.test"
        )

        try database.saveProfiles([first, second])

        let reloaded = try database.loadProfiles()
        #expect(reloaded == [first, second])
    }
}
