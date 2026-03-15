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
            return "手动检查"
        case .daily:
            return "每天自动检查"
        case .onLaunch:
            return "启动时检查"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultUpdateCheckStrategy: UpdateCheckStrategy = .daily
    static let defaultEditorFontSize: Double = 13
    static let editorFontSizeStep: Double = 1
    static let minEditorFontSize: Double = 11
    static let maxEditorFontSize: Double = 24
    static let defaultSidebarWidth: Double = 220
    static let minSidebarWidth: Double = 160
    static let maxSidebarWidth: Double = 420

    private enum Keys {
        static let updateCheckStrategy = "HostsEditorUpdateCheckStrategy"
        static let editorFontSize = "HostsEditorEditorFontSize"
        static let sidebarWidth = "HostsEditorSidebarWidth"
    }

    @Published var updateCheckStrategy: UpdateCheckStrategy {
        didSet {
            guard oldValue != updateCheckStrategy else { return }
            UserDefaults.standard.set(updateCheckStrategy.rawValue, forKey: Keys.updateCheckStrategy)
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
            UserDefaults.standard.set(editorFontSize, forKey: Keys.editorFontSize)
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
            UserDefaults.standard.set(sidebarWidth, forKey: Keys.sidebarWidth)
        }
    }

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: Keys.updateCheckStrategy),
           let strategy = UpdateCheckStrategy(rawValue: rawValue) {
            updateCheckStrategy = strategy
        } else {
            updateCheckStrategy = Self.defaultUpdateCheckStrategy
        }

        if UserDefaults.standard.object(forKey: Keys.editorFontSize) != nil {
            editorFontSize = Self.clampedEditorFontSize(UserDefaults.standard.double(forKey: Keys.editorFontSize))
        } else {
            editorFontSize = Self.defaultEditorFontSize
        }

        if UserDefaults.standard.object(forKey: Keys.sidebarWidth) != nil {
            sidebarWidth = Self.clampedSidebarWidth(UserDefaults.standard.double(forKey: Keys.sidebarWidth))
        } else {
            sidebarWidth = Self.defaultSidebarWidth
        }
    }

    func resetToDefaults() {
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
