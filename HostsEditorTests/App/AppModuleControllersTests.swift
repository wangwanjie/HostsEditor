import AppKit
import Testing
@testable import HostsEditor

struct AppModuleControllersTests {
    @MainActor
    @Test
    func mainWindowControllerReopensClosedMainWindowUsingSameWindowInstance() throws {
        let controller = MainWindowController()

        controller.showWindow(nil)
        let initialWindow = try #require(controller.window)
        controller.closeWindow()

        controller.showWindow(nil)

        #expect(controller.window === initialWindow)
        #expect(controller.window?.isVisible == true)
    }

    @MainActor
    @Test
    func mainMenuControllerBuildsExpectedTopLevelMenus() {
        let controller = MainMenuController(
            openPreferencesHandler: {},
            installHelperHandler: {},
            uninstallHelperHandler: {},
            checkForUpdatesHandler: {},
            openHelpHandler: {}
        )

        controller.install()

        let items = NSApp.mainMenu?.items ?? []
        #expect(items.count >= 5)
        let titles = items.map(\.title)
        #expect(titles.contains(L10n.tr("menu.file")))
        #expect(titles.contains(L10n.tr("menu.edit")))
        #expect(titles.contains(L10n.tr("menu.window")))
        #expect(titles.contains(L10n.tr("menu.help")))
    }

    @MainActor
    @Test
    func statusItemControllerBuildsStatusMenuIncludingProfiles() throws {
        let database = try AppDatabase.inMemory()
        let manager = HostsManager(database: database)
        manager.addProfile(HostsProfile(name: "Local Profile", content: "127.0.0.1 local.test"))

        let controller = StatusItemController(
            manager: manager,
            updateManager: .shared,
            openMainWindowHandler: {},
            openPreferencesHandler: {}
        )

        #expect(controller.debugMenuTitles.contains(L10n.tr("status.open_main_window")))
        #expect(controller.debugMenuTitles.contains("Local Profile"))
        #expect(controller.debugMenuTitles.contains(L10n.tr("status.quit")))
    }
}
