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

/// 远程方案自动刷新间隔
enum RemoteRefreshInterval: String, CaseIterable {
    case off
    case hourly
    case everySixHours
    case daily

    /// 刷新间隔秒数；关闭时为 nil
    var seconds: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .hourly:
            return 60 * 60
        case .everySixHours:
            return 6 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .off:
            return L10n.tr("settings.remote_refresh.off")
        case .hourly:
            return L10n.tr("settings.remote_refresh.hourly")
        case .everySixHours:
            return L10n.tr("settings.remote_refresh.six_hours")
        case .daily:
            return L10n.tr("settings.remote_refresh.daily")
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
    static let defaultRemoteRefreshInterval: RemoteRefreshInterval = .off

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

    @Published var remoteRefreshInterval: RemoteRefreshInterval {
        didSet {
            guard oldValue != remoteRefreshInterval else {
                return
            }
            persistSetting(.remoteRefreshInterval, value: .string(remoteRefreshInterval.rawValue))
        }
    }

    init(database: AppDatabase? = nil) {
        self.database = database ?? .shared

        appLanguage = Self.defaultLanguage
        appAppearance = Self.defaultAppearance
        updateCheckStrategy = Self.defaultUpdateCheckStrategy
        editorFontSize = Self.defaultEditorFontSize
        sidebarWidth = Self.defaultSidebarWidth
        remoteRefreshInterval = Self.defaultRemoteRefreshInterval

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
        remoteRefreshInterval = Self.defaultRemoteRefreshInterval
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

            if case .string(let rawInterval)? = try database.settingValue(.remoteRefreshInterval),
               let interval = RemoteRefreshInterval(rawValue: rawInterval) {
                remoteRefreshInterval = interval
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
