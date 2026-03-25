import AppKit
import Testing
@testable import HostsEditor

struct AppDelegateWindowTests {
    @MainActor
    @Test
    func dockReopenShowsMainWindowWhenNoVisibleWindowExists() throws {
        let appDelegate = AppDelegate()
        appDelegate.loadMainWindowControllerForTesting()
        appDelegate.closeMainWindowForTesting()

        let handled = appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)

        #expect(handled)
        #expect(appDelegate.debugMainWindow?.isVisible == true)
    }
}
