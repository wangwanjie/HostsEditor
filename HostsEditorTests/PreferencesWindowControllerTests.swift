import AppKit
import Foundation
import Testing
@testable import HostsEditor

@Suite(.serialized)
struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func preferencesRefreshesLocalizedTitlesWhenLanguageChanges() throws {
        let database = try AppDatabase.inMemory()

        let originalLanguage = AppLocalization.shared.language
        let originalAppearance = NSApplication.shared.appearance

        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
            NSApplication.shared.appearance = originalAppearance
        }

        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.loadWindow()

        #expect(controller.window?.title == "偏好设置")
        #expect(controller.debugSectionLabels == ["通用", "更新", "编辑器", "帮助程序"])
        #expect(controller.debugLanguagePopup.itemTitles == ["English", "简体中文", "繁體中文"])
        #expect(controller.debugAppearancePopup.itemTitles == ["跟随系统", "浅色", "深色"])

        settings.appLanguage = .english

        try waitUntil(description: "preferences localization updated") {
            controller.window?.title == "Preferences"
                && controller.debugSectionLabels == ["General", "Updates", "Editor", "Helper"]
                && controller.debugAppearancePopup.itemTitles == ["System", "Light", "Dark"]
        }
    }

    @MainActor
    @Test
    func preferencesFollowsRuntimeAppearanceSelection() throws {
        let database = try AppDatabase.inMemory()

        let originalLanguage = AppLocalization.shared.language
        let originalAppearance = NSApplication.shared.appearance

        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
            NSApplication.shared.appearance = originalAppearance
        }

        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.loadWindow()

        settings.appAppearance = .dark

        try waitUntil(description: "preferences effective appearance updated") {
            controller.debugEffectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    @MainActor
    @Test
    func preferencesRecomputesSegmentWidthsWhenLanguageChanges() throws {
        let database = try AppDatabase.inMemory()

        let originalLanguage = AppLocalization.shared.language
        let originalAppearance = NSApplication.shared.appearance

        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
            NSApplication.shared.appearance = originalAppearance
        }

        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.loadWindow()

        let segmentedControl = try #require(findSegmentedControl(in: controller.window))
        let initialWidths = segmentWidths(for: segmentedControl)

        settings.appLanguage = .english

        try waitUntil(description: "preferences segment widths updated") {
            let updatedWidths = segmentWidths(for: segmentedControl)
            return controller.debugSectionLabels == ["General", "Updates", "Editor", "Helper"]
                && updatedWidths != initialWidths
                && updatedWidths[0] > initialWidths[0]
                && updatedWidths[1] > initialWidths[1]
        }
    }

    @MainActor
    @Test
    func preferencesAnimatesWindowHeightWhenSwitchingSections() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.loadWindow()

        let initialHeight = try #require(controller.window?.frame.height)
        controller.selectSectionForTesting(index: 3)

        try waitUntil(description: "preferences resized after section switch") {
            guard let updatedHeight = controller.window?.frame.height else { return false }
            return abs(updatedHeight - initialHeight) > 1
        }
    }
}

@MainActor
private func findSegmentedControl(in window: NSWindow?) -> NSSegmentedControl? {
    guard let contentView = window?.contentView else { return nil }
    return findSegmentedControl(in: contentView)
}

@MainActor
private func findSegmentedControl(in view: NSView) -> NSSegmentedControl? {
    if let segmentedControl = view as? NSSegmentedControl {
        return segmentedControl
    }

    for subview in view.subviews {
        if let segmentedControl = findSegmentedControl(in: subview) {
            return segmentedControl
        }
    }

    return nil
}

@MainActor
private func segmentWidths(for control: NSSegmentedControl) -> [CGFloat] {
    (0..<control.segmentCount).map { control.width(forSegment: $0) }
}
