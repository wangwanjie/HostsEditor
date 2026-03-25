import AppKit
import Foundation
import Testing
@testable import HostsEditor

struct ViewControllerHighlightingTests {
    @MainActor
    @Test
    func selectedRemoteProfileRefreshesVisibleEditorContentAndRehighlights() throws {
        let database = try AppDatabase.inMemory()
        let remoteProfile = HostsProfile(
            id: "remote-profile",
            name: "Remote",
            content: "127.0.0.1 before.test",
            isEnabled: false,
            isRemote: true,
            remoteURL: "https://example.test/hosts"
        )
        try database.saveProfiles([remoteProfile])

        let manager = HostsManager(database: database)
        let settings = AppSettings(database: database)
        let controller = ViewController(manager: manager, settings: settings)
        let window = NSWindow(contentViewController: controller)
        _ = window.contentView

        controller.selectProfileForTesting(id: remoteProfile.id)
        manager.updateProfile(id: remoteProfile.id, content: "127.0.0.1 after.test")
        controller.handleProfilesDidChangeForTesting()

        try waitUntil(description: "remote profile editor content refreshed") {
            controller.debugEditorString.contains("after.test") && controller.debugDidTriggerFullRehighlight
        }
    }
}
