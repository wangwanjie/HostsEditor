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
        controller.showPreferencesWindow()

        let segmentedControl = try #require(findSegmentedControl(in: controller.window))
        try waitUntil(description: "preferences window visible") {
            controller.window?.isVisible == true
        }

        let initialSegmentWidths = segmentWidths(for: segmentedControl)
        let initialControlWidth = segmentedControl.frame.width

        settings.appLanguage = .english

        try waitUntil(description: "preferences segment widths updated") {
            segmentedControl.layoutSubtreeIfNeeded()
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            let updatedSegmentWidths = segmentWidths(for: segmentedControl)
            let updatedControlWidth = segmentedControl.frame.width
            return controller.debugSectionLabels == ["General", "Updates", "Editor", "Helper"]
                && updatedSegmentWidths.count == initialSegmentWidths.count
                && updatedSegmentWidths != initialSegmentWidths
                && updatedSegmentWidths[0] > initialSegmentWidths[0]
                && updatedSegmentWidths[1] > initialSegmentWidths[1]
                && updatedControlWidth > initialControlWidth
        }
    }

    @MainActor
    @Test
    func preferencesAnimatesWindowHeightWhenSwitchingSections() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.showPreferencesWindow()

        try waitUntil(description: "preferences window visible for section animation") {
            controller.window?.isVisible == true
        }

        let initialHeight = try #require(controller.window?.frame.height)
        controller.selectSectionForTesting(index: 1)

        try waitUntil(description: "preferences resized after section switch") {
            guard let updatedHeight = controller.window?.frame.height else { return false }
            return abs(updatedHeight - initialHeight) > 1
        }
    }

    @MainActor
    @Test
    func preferencesOnlyAttachesCurrentSectionCardIntoContainer() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.showPreferencesWindow()

        try waitUntil(description: "preferences window visible for section container check") {
            controller.window?.isVisible == true
        }

        let contentView = try #require(controller.window?.contentView)
        #expect(findPreferenceCardViews(in: contentView).count == 1)
    }

    @MainActor
    @Test
    func preferencesDoesNotKeepCollapsedHeightConstraintOnSectionContainer() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.showPreferencesWindow()

        try waitUntil(description: "preferences window visible for section container constraint check") {
            controller.window?.isVisible == true
        }

        let sectionContainer = try #require(findPreferencesSectionContainer(in: controller.window))
        let hasCollapsedHeightConstraint = sectionContainer.constraints.contains {
            $0.firstItem as? NSView === sectionContainer
                && $0.firstAttribute == .height
                && $0.relation == .equal
                && abs($0.constant) < 0.5
        }

        #expect(hasCollapsedHeightConstraint == false)
    }

    @MainActor
    @Test
    func preferencesKeepsVisibleSectionScreenTopStableDuringWindowResizeAnimation() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.showPreferencesWindow()

        try waitUntil(description: "preferences window visible for screen top sampling") {
            controller.window?.isVisible == true
        }

        let contentView = try #require(controller.window?.contentView)
        let sampledScreenTopValues = try sampleVisibleSectionScreenTopValues(in: contentView, while: {
            controller.selectSectionForTesting(index: 1)
        })

        #expect(sampledScreenTopValues.count <= 2)
    }

    @MainActor
    @Test
    func preferencesFitsInitialWindowHeightAfterFirstShow() throws {
        let database = try AppDatabase.inMemory()
        let settings = AppSettings(database: database)
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)

        controller.showPreferencesWindow()

        try waitUntil(description: "preferences window visible for initial fit") {
            controller.window?.isVisible == true
        }

        let segmentedControl = try #require(findSegmentedControl(in: controller.window))
        let contentView = try #require(controller.window?.contentView)
        let visibleSection = try #require(findVisiblePreferenceSection(in: contentView))
        contentView.layoutSubtreeIfNeeded()
        segmentedControl.layoutSubtreeIfNeeded()
        visibleSection.layoutSubtreeIfNeeded()

        let minimumContentHeight = controller.window?.contentRect(
            forFrameRect: NSRect(origin: .zero, size: controller.window?.minSize ?? .zero)
        ).height ?? 0
        let expectedContentHeight = max(
            minimumContentHeight,
            ceil(segmentedControl.fittingSize.height + visibleSection.fittingSize.height + 44 + 18)
        )
        let expectedFrameHeight = controller.window?.frameRect(
            forContentRect: NSRect(origin: .zero, size: NSSize(width: 620, height: expectedContentHeight))
        ).height
        let actualFrameHeight = try #require(controller.window?.frame.height)

        #expect(abs(actualFrameHeight - (expectedFrameHeight ?? 0)) <= 1)
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
private func findPreferenceCardViews(in view: NSView) -> [NSView] {
    var matches: [NSView] = []
    if view.layer?.cornerRadius == 12 {
        matches.append(view)
    }

    for subview in view.subviews {
        matches.append(contentsOf: findPreferenceCardViews(in: subview))
    }

    return matches
}

@MainActor
private func segmentWidths(for control: NSSegmentedControl) -> [CGFloat] {
    (0..<control.segmentCount).map { control.width(forSegment: $0) }
}

@MainActor
private func sampleVisibleSectionScreenTopValues(in contentView: NSView, while action: () -> Void) throws -> [CGFloat] {
    action()

    var sampledValues: [CGFloat] = []
    let deadline = Date().addingTimeInterval(0.35)
    while Date() < deadline {
        contentView.layoutSubtreeIfNeeded()
        guard let visibleSection = findVisiblePreferenceSection(in: contentView),
              let window = visibleSection.window else {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            continue
        }

        let sectionRectInWindow = visibleSection.convert(visibleSection.bounds, to: nil)
        let sectionRectOnScreen = window.convertToScreen(sectionRectInWindow)
        let roundedTop = (sectionRectOnScreen.maxY * 10).rounded() / 10
        if sampledValues.last != roundedTop {
            sampledValues.append(roundedTop)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    if sampledValues.isEmpty {
        throw NSError(
            domain: "HostsEditorTests.Sampling",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to sample preferences visible section screen top during window animation."]
        )
    }

    return sampledValues
}

@MainActor
private func findVisiblePreferenceSection(in view: NSView) -> NSView? {
    if view.isHidden == false,
       view.layer?.cornerRadius == 12 {
        return view
    }

    for subview in view.subviews {
        if let match = findVisiblePreferenceSection(in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func findPreferencesSectionContainer(in window: NSWindow?) -> NSView? {
    guard let contentView = window?.contentView else { return nil }
    return findPreferencesSectionContainer(in: contentView)
}

@MainActor
private func findPreferencesSectionContainer(in view: NSView) -> NSView? {
    if view.identifier?.rawValue == "preferences.sectionContainer" {
        return view
    }

    for subview in view.subviews {
        if let match = findPreferencesSectionContainer(in: subview) {
            return match
        }
    }

    return nil
}
