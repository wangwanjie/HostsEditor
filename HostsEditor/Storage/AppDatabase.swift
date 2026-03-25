import Foundation
import GRDB

final class AppDatabase {
    static let shared: AppDatabase = {
        do {
            return try AppDatabase(configuration: AppDatabaseConfiguration(databasePath: defaultDatabasePath()))
        } catch {
            fatalError("Failed to initialize AppDatabase.shared: \(error)")
        }
    }()

    let dbQueue: DatabaseQueue

    init(configuration: AppDatabaseConfiguration) throws {
        dbQueue = try DatabaseQueue(path: configuration.databasePath)
        try migrator.migrate(dbQueue)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(configuration: .inMemory())
    }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    func saveSetting(_ key: AppSettingKey, value: AppSettingValue, db: Database) throws {
        var record = try AppSettingRecord(key: key, value: value)
        try record.save(db)
    }

    func saveSetting(_ key: AppSettingKey, value: AppSettingValue) throws {
        try write { db in
            try saveSetting(key, value: value, db: db)
        }
    }

    func settingValue(_ key: AppSettingKey, db: Database) throws -> AppSettingValue? {
        guard let record = try AppSettingRecord.fetchOne(db, key: key.rawValue) else {
            return nil
        }
        return try record.decodedValue()
    }

    func settingValue(_ key: AppSettingKey) throws -> AppSettingValue? {
        try read { db in
            try settingValue(key, db: db)
        }
    }

    func saveProfiles(_ profiles: [HostsProfile]) throws {
        try write { db in
            try replaceProfiles(profiles, db: db)
        }
    }

    func loadProfiles() throws -> [HostsProfile] {
        try read { db in
            try ProfileRecord
                .order(Column("sort_index").asc)
                .fetchAll(db)
                .map(\.hostsProfile)
        }
    }

    func replaceProfiles(_ profiles: [HostsProfile], db: Database) throws {
        try ProfileRecord.deleteAll(db)
        for (index, profile) in profiles.enumerated() {
            var record = ProfileRecord(profile: profile, sortIndex: index)
            try record.insert(db)
        }
    }

    func runStartupMigrationIfNeeded(defaults: UserDefaults = .standard) throws {
        try BusinessDataMigrator(defaults: defaults, database: self).migrateIfNeeded()
    }

    private static func defaultDatabasePath(fileManager: FileManager = .default) throws -> String {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseDirectory = appSupportURL.appendingPathComponent("HostsEditor", isDirectory: true)
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        return databaseDirectory.appendingPathComponent("hostseditor.sqlite").path
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_profiles_and_app_settings") { db in
            try db.create(table: ProfileRecord.databaseTableName) { table in
                table.column("sort_index", .integer).notNull()
                table.column("id", .text).notNull().primaryKey()
                table.column("name", .text).notNull()
                table.column("content", .text).notNull()
                table.column("isEnabled", .boolean).notNull()
                table.column("isRemote", .boolean).notNull()
                table.column("remoteURL", .text)
                table.column("lastUpdated", .datetime)
            }

            try db.create(table: AppSettingRecord.databaseTableName) { table in
                table.column("key", .text).notNull().primaryKey()
                table.column("value", .text).notNull()
            }
        }
        return migrator
    }
}
