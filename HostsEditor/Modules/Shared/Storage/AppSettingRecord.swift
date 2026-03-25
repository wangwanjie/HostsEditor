import Foundation
import GRDB

enum AppSettingKey: String, Codable, CaseIterable {
    case baseSystemContent = "base_system_content"
    case appLanguage = "app_language"
    case appAppearance = "app_appearance"
    case updateCheckStrategy = "update_check_strategy"
    case editorFontSize = "editor_font_size"
    case sidebarWidth = "sidebar_width"

    var legacyUserDefaultsKey: String {
        switch self {
        case .baseSystemContent:
            return "HostsEditorBaseContent"
        case .appLanguage:
            return "HostsEditorAppLanguage"
        case .appAppearance:
            return "HostsEditorAppAppearance"
        case .updateCheckStrategy:
            return "HostsEditorUpdateCheckStrategy"
        case .editorFontSize:
            return "HostsEditorEditorFontSize"
        case .sidebarWidth:
            return "HostsEditorSidebarWidth"
        }
    }
}

enum AppSettingValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case int(Int)
}

struct AppSettingRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "app_settings"

    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    init(key: AppSettingKey, value: AppSettingValue) throws {
        self.key = key.rawValue
        guard let encodedValue = String(data: try Self.encoder.encode(value), encoding: .utf8) else {
            throw DatabaseError(message: "Failed to encode app_settings value for key: \(key.rawValue)")
        }
        self.value = encodedValue
    }

    func decodedValue() throws -> AppSettingValue {
        guard let data = value.data(using: .utf8) else {
            throw DatabaseError(message: "Invalid UTF-8 app_settings value for key: \(key)")
        }
        return try Self.decoder.decode(AppSettingValue.self, from: data)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
