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

    private enum Keys {
        static let updateCheckStrategy = "HostsEditorUpdateCheckStrategy"
        static let appLanguage = "HostsEditorAppLanguage"
        static let appAppearance = "HostsEditorAppAppearance"
        static let editorFontSize = "HostsEditorEditorFontSize"
        static let sidebarWidth = "HostsEditorSidebarWidth"
    }

    private let defaults: UserDefaults

    @Published var appLanguage: AppLanguage {
        didSet {
            guard oldValue != appLanguage else { return }
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            AppLocalization.shared.setLanguage(appLanguage)
        }
    }

    @Published var appAppearance: AppAppearance {
        didSet {
            guard oldValue != appAppearance else { return }
            defaults.set(appAppearance.rawValue, forKey: Keys.appAppearance)
            AppearanceManager.shared.apply(appAppearance)
        }
    }

    @Published var updateCheckStrategy: UpdateCheckStrategy {
        didSet {
            guard oldValue != updateCheckStrategy else { return }
            defaults.set(updateCheckStrategy.rawValue, forKey: Keys.updateCheckStrategy)
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
            defaults.set(editorFontSize, forKey: Keys.editorFontSize)
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
            defaults.set(sidebarWidth, forKey: Keys.sidebarWidth)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawLanguage = defaults.string(forKey: Keys.appLanguage),
           let language = AppLanguage(rawValue: rawLanguage) {
            appLanguage = language
        } else {
            appLanguage = Self.defaultLanguage
        }

        if let rawAppearance = defaults.string(forKey: Keys.appAppearance),
           let appearance = AppAppearance(rawValue: rawAppearance) {
            appAppearance = appearance
        } else {
            appAppearance = Self.defaultAppearance
        }

        if let rawValue = defaults.string(forKey: Keys.updateCheckStrategy),
           let strategy = UpdateCheckStrategy(rawValue: rawValue) {
            updateCheckStrategy = strategy
        } else {
            updateCheckStrategy = Self.defaultUpdateCheckStrategy
        }

        if defaults.object(forKey: Keys.editorFontSize) != nil {
            editorFontSize = Self.clampedEditorFontSize(defaults.double(forKey: Keys.editorFontSize))
        } else {
            editorFontSize = Self.defaultEditorFontSize
        }

        if defaults.object(forKey: Keys.sidebarWidth) != nil {
            sidebarWidth = Self.clampedSidebarWidth(defaults.double(forKey: Keys.sidebarWidth))
        } else {
            sidebarWidth = Self.defaultSidebarWidth
        }

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
}
