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
    func fileMenuItemsAreWiredToMainInterfaceActions() throws {
        let controller = MainMenuController(
            openPreferencesHandler: {},
            installHelperHandler: {},
            uninstallHelperHandler: {},
            checkForUpdatesHandler: {},
            openHelpHandler: {}
        )
        controller.install()

        let fileMenu = try #require(NSApp.mainMenu?.items.first { $0.title == L10n.tr("menu.file") }?.submenu)
        let actionsByTitle = Dictionary(
            fileMenu.items.filter { !$0.isSeparatorItem }.map { ($0.title, $0.action) },
            uniquingKeysWith: { first, _ in first }
        )

        // 不允许出现没有动作的“死”菜单项
        #expect(fileMenu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.action != nil })
        #expect(actionsByTitle[L10n.tr("menu.new_local_profile")] == #selector(ViewController.newLocalProfileFromMenu(_:)))
        #expect(actionsByTitle[L10n.tr("menu.import")] == #selector(ViewController.importProfileFromFile(_:)))
        #expect(actionsByTitle[L10n.tr("menu.save_and_apply")] == #selector(ViewController.saveAndApplyFromMenu(_:)))
        #expect(actionsByTitle[L10n.tr("menu.export")] == #selector(ViewController.exportCurrentContent(_:)))
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

        // “打开主窗口”必须显式指定 target，不能依赖响应链
        let openItem = try #require(controller.debugMenuItems.first { $0.title == L10n.tr("status.open_main_window") })
        #expect(openItem.target === controller)
    }

    @MainActor
    @Test
    func statusItemHidesProfileSeparatorWhenThereAreNoProfiles() async throws {
        let database = try AppDatabase.inMemory()
        let manager = HostsManager(database: database, privilegedWriter: FakePrivilegedHostsWriter(), notificationCenter: NotificationCenter())
        // 删除全部（未启用的）方案，构造空列表
        for profile in manager.profiles {
            _ = await manager.deleteProfile(id: profile.id)
        }
        #expect(manager.profiles.isEmpty)
        let controller = StatusItemController(
            manager: manager,
            updateManager: .shared,
            openMainWindowHandler: {},
            openPreferencesHandler: {}
        )

        let visibleItems = controller.debugMenuItems.filter { !$0.isHidden }
        // 相邻两个可见分隔线说明菜单出现了空分组
        let hasAdjacentSeparators = zip(visibleItems, visibleItems.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem }
        #expect(!hasAdjacentSeparators)
    }
}
