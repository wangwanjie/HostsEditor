import Foundation

struct BusinessDataMigrator {
    enum MigrationError: Error {
        case verificationFailed
    }

    struct Snapshot: Equatable {
        var profiles: [HostsProfile]
        var settings: [AppSettingKey: AppSettingValue]
    }

    private enum LegacyKey {
        static let profiles = "HostsEditorProfiles"
    }

    private let defaults: UserDefaults
    private let database: AppDatabase
    private let verifier: (Snapshot, Snapshot) -> Bool

    init(
        defaults: UserDefaults = .standard,
        database: AppDatabase,
        verifier: ((Snapshot, Snapshot) -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.database = database
        self.verifier = verifier ?? { $0 == $1 }
    }

    func migrateIfNeeded() throws {
        guard hasLegacyBusinessData else { return }

        let snapshot = try readLegacySnapshot()
        try database.write { db in
            if defaults.object(forKey: LegacyKey.profiles) != nil {
                try database.replaceProfiles(snapshot.profiles, db: db)
            }

            for key in AppSettingKey.allCases {
                guard let value = snapshot.settings[key] else { continue }
                try database.saveSetting(key, value: value, db: db)
            }
        }

        let migratedSnapshot = try readDatabaseSnapshot(using: snapshot)
        guard verifier(snapshot, migratedSnapshot) else {
            throw MigrationError.verificationFailed
        }

        clearLegacyBusinessKeys()
    }

    private var hasLegacyBusinessData: Bool {
        if defaults.object(forKey: LegacyKey.profiles) != nil {
            return true
        }

        return AppSettingKey.allCases.contains { defaults.object(forKey: $0.legacyUserDefaultsKey) != nil }
    }

    private func readLegacySnapshot() throws -> Snapshot {
        var settings: [AppSettingKey: AppSettingValue] = [:]

        if let baseSystemContent = defaults.string(forKey: AppSettingKey.baseSystemContent.legacyUserDefaultsKey) {
            settings[.baseSystemContent] = .string(baseSystemContent)
        }

        if let updateCheckStrategy = defaults.string(forKey: AppSettingKey.updateCheckStrategy.legacyUserDefaultsKey) {
            settings[.updateCheckStrategy] = .string(updateCheckStrategy)
        }

        if let appLanguage = defaults.string(forKey: AppSettingKey.appLanguage.legacyUserDefaultsKey) {
            settings[.appLanguage] = .string(appLanguage)
        }

        if let appAppearance = defaults.string(forKey: AppSettingKey.appAppearance.legacyUserDefaultsKey) {
            settings[.appAppearance] = .string(appAppearance)
        }

        if defaults.object(forKey: AppSettingKey.editorFontSize.legacyUserDefaultsKey) != nil {
            settings[.editorFontSize] = .double(defaults.double(forKey: AppSettingKey.editorFontSize.legacyUserDefaultsKey))
        }

        if defaults.object(forKey: AppSettingKey.sidebarWidth.legacyUserDefaultsKey) != nil {
            settings[.sidebarWidth] = .double(defaults.double(forKey: AppSettingKey.sidebarWidth.legacyUserDefaultsKey))
        }

        let profiles: [HostsProfile]
        if let data = defaults.data(forKey: LegacyKey.profiles) {
            profiles = try JSONDecoder().decode([HostsProfile].self, from: data)
        } else {
            profiles = []
        }

        return Snapshot(profiles: profiles, settings: settings)
    }

    private func readDatabaseSnapshot(using source: Snapshot) throws -> Snapshot {
        let profiles = defaults.object(forKey: LegacyKey.profiles) != nil ? try database.loadProfiles() : []
        var settings: [AppSettingKey: AppSettingValue] = [:]

        for key in source.settings.keys {
            settings[key] = try database.settingValue(key)
        }

        return Snapshot(profiles: profiles, settings: settings)
    }

    private func clearLegacyBusinessKeys() {
        defaults.removeObject(forKey: LegacyKey.profiles)
        AppSettingKey.allCases.forEach { defaults.removeObject(forKey: $0.legacyUserDefaultsKey) }
    }
}
