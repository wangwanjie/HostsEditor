import AppKit
import Foundation
import Testing
@testable import HostsEditor

@Suite(.serialized)
struct RuntimeLocalizationTests {
    @MainActor
    @Test
    func mainViewRefreshesLocalizedControlsWhenLanguageChanges() throws {
        let originalLanguage = AppLocalization.shared.language
        defer {
            AppLocalization.shared.setLanguage(originalLanguage)
        }

        AppLocalization.shared.setLanguage(.simplifiedChinese)

        let controller = ViewController()
        controller.loadViewIfNeeded()

        #expect(controller.debugApplyButtonTitle == "保存并应用")
        #expect(controller.debugAddProfileButtonTitle == "新建")
        #expect(controller.debugSidebarTitle == "方案")
        #expect(controller.debugFindPlaceholder == "查找")
        #expect(controller.debugReplacePlaceholder == "替换")

        AppLocalization.shared.setLanguage(.english)

        try waitUntil(description: "main view localization updated") {
            controller.debugApplyButtonTitle == "Save and Apply"
                && controller.debugAddProfileButtonTitle == "Add"
                && controller.debugSidebarTitle == "Profiles"
                && controller.debugFindPlaceholder == "Find"
                && controller.debugReplacePlaceholder == "Replace"
        }
    }
}
