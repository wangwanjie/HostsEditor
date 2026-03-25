import Foundation

struct AppDatabaseConfiguration {
    let databasePath: String

    static func inMemory() -> AppDatabaseConfiguration {
        AppDatabaseConfiguration(databasePath: ":memory:")
    }
}
