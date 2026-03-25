//
//  AppSettings.swift
//  HostsEditor
//

import Foundation
import Combine

enum UpdateCheckStrategy: String, CaseIterable {
    case manual
    case daily
    case onLaunch

    var title: String {
        switch self {
        case .manual:
            return L10n.updateStrategyManual
        case .daily:
            return L10n.updateStrategyDaily
        case .onLaunch:
            return L10n.updateStrategyOnLaunch
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultUpdateCheckStrategy: UpdateCheckStrategy = .daily
    static let defaultLanguage: AppLanguage = .simplifiedChinese
    static let defaultAppearance: AppAppearance = .system
    static let defaultEditorFontSize: Double = 13
    static let editorFontSizeStep: Double = 1
    static let minEditorFontSize: Double = 11
    static let maxEditorFontSize: Double = 24
    static let defaultSidebarWidth: Double = 220
    static let minSidebarWidth: Double = 160
    static let maxSidebarWidth: Double = 420

    private let database: AppDatabase

    @Published var appLanguage: AppLanguage {
        didSet {
            guard oldValue != appLanguage else { return }
            persistSetting(.appLanguage, value: .string(appLanguage.rawValue))
            AppLocalization.shared.setLanguage(appLanguage)
        }
    }

    @Published var appAppearance: AppAppearance {
        didSet {
            guard oldValue != appAppearance else { return }
            persistSetting(.appAppearance, value: .string(appAppearance.rawValue))
            AppearanceManager.shared.apply(appAppearance)
        }
    }

    @Published var updateCheckStrategy: UpdateCheckStrategy {
        didSet {
            guard oldValue != updateCheckStrategy else { return }
            persistSetting(.updateCheckStrategy, value: .string(updateCheckStrategy.rawValue))
        }
    }

    @Published var editorFontSize: Double {
        didSet {
            let clampedValue = Self.clampedEditorFontSize(editorFontSize)
            if editorFontSize != clampedValue {
                editorFontSize = clampedValue
                return
            }
            guard oldValue != editorFontSize else { return }
            persistSetting(.editorFontSize, value: .double(editorFontSize))
        }
    }

    @Published var sidebarWidth: Double {
        didSet {
            let clampedValue = Self.clampedSidebarWidth(sidebarWidth)
            if sidebarWidth != clampedValue {
                sidebarWidth = clampedValue
                return
            }
            guard oldValue != sidebarWidth else { return }
            persistSetting(.sidebarWidth, value: .double(sidebarWidth))
        }
    }

    init(database: AppDatabase? = nil) {
        self.database = database ?? .shared

        appLanguage = Self.defaultLanguage
        appAppearance = Self.defaultAppearance
        updateCheckStrategy = Self.defaultUpdateCheckStrategy
        editorFontSize = Self.defaultEditorFontSize
        sidebarWidth = Self.defaultSidebarWidth

        loadPersistedValues()

        AppLocalization.shared.setLanguage(appLanguage)
        AppearanceManager.shared.apply(appAppearance)
    }

    func resetToDefaults() {
        appLanguage = Self.defaultLanguage
        appAppearance = Self.defaultAppearance
        updateCheckStrategy = Self.defaultUpdateCheckStrategy
        editorFontSize = Self.defaultEditorFontSize
        sidebarWidth = Self.defaultSidebarWidth
    }

    func adjustEditorFontSize(by delta: Double) {
        editorFontSize = Self.adjustedEditorFontSize(editorFontSize, delta: delta)
    }

    static func clampedEditorFontSize(_ pointSize: Double) -> Double {
        min(max(pointSize.rounded(), minEditorFontSize), maxEditorFontSize)
    }

    static func adjustedEditorFontSize(_ pointSize: Double, delta: Double) -> Double {
        clampedEditorFontSize(pointSize + delta)
    }

    static func clampedSidebarWidth(_ width: Double) -> Double {
        min(max(width.rounded(), minSidebarWidth), maxSidebarWidth)
    }

    private func loadPersistedValues() {
        do {
            if case .string(let rawLanguage)? = try database.settingValue(.appLanguage),
               let language = AppLanguage(rawValue: rawLanguage) {
                appLanguage = language
            }

            if case .string(let rawAppearance)? = try database.settingValue(.appAppearance),
               let appearance = AppAppearance(rawValue: rawAppearance) {
                appAppearance = appearance
            }

            if case .string(let rawStrategy)? = try database.settingValue(.updateCheckStrategy),
               let strategy = UpdateCheckStrategy(rawValue: rawStrategy) {
                updateCheckStrategy = strategy
            }

            if case .double(let storedFontSize)? = try database.settingValue(.editorFontSize) {
                editorFontSize = Self.clampedEditorFontSize(storedFontSize)
            }

            if case .double(let storedSidebarWidth)? = try database.settingValue(.sidebarWidth) {
                sidebarWidth = Self.clampedSidebarWidth(storedSidebarWidth)
            }
        } catch {
            NSLog("Failed to load AppSettings from database: %@", String(describing: error))
        }
    }

    private func persistSetting(_ key: AppSettingKey, value: AppSettingValue) {
        do {
            try database.saveSetting(key, value: value)
        } catch {
            NSLog("Failed to persist AppSettings key %@: %@", key.rawValue, String(describing: error))
        }
    }
}
