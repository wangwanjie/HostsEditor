//
//  AppDelegate.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var mainMenuController: MainMenuController?
    private var statusItemController: StatusItemController?
    private lazy var preferencesWindowController = PreferencesWindowController.shared
    private let helperInterventionCoordinator = HelperInterventionCoordinator()
    private var remoteProfileAutoRefresher: RemoteProfileAutoRefresher?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 测试运行时使用内存数据库，不迁移也不清理用户真实的旧版 UserDefaults 数据
        if !AppEnvironment.isRunningTests {
            do {
                try AppDatabase.shared.runStartupMigrationIfNeeded()
            } catch {
                NSLog("Business data migration failed: %@", String(describing: error))
            }
        }

        _ = AppSettings.shared

        // 测试宿主中不监听 Helper 干预通知，避免测试触发模态弹窗
        if !AppEnvironment.isRunningTests {
            helperInterventionCoordinator.startObserving()
        }
        mainWindowController = MainWindowController()
        mainMenuController = MainMenuController(
            openPreferencesHandler: { [weak self] in self?.openPreferencesWindow() },
            installHelperHandler: { [weak self] in self?.installHelperFromMenu() },
            uninstallHelperHandler: { [weak self] in self?.uninstallHelperFromMenu() },
            checkForUpdatesHandler: { [weak self] in self?.checkForUpdates() },
            openHelpHandler: { [weak self] in self?.openGitHubHomepage() }
        )
        statusItemController = StatusItemController(
            manager: .shared,
            updateManager: .shared,
            openMainWindowHandler: { [weak self] in self?.openMainWindow() },
            openPreferencesHandler: { [weak self] in self?.openPreferencesWindow() }
        )
        UpdateManager.shared.configure()

        // 单元测试 / UI 测试宿主启动时跳过会弹窗或访问网络的流程，避免阻塞测试
        guard !AppEnvironment.isRunningTests else {
            return
        }

        UpdateManager.shared.scheduleBackgroundUpdateCheck()
        let refresher = RemoteProfileAutoRefresher(manager: .shared, settings: .shared)
        refresher.start()
        remoteProfileAutoRefresher = refresher
        DispatchQueue.main.async { [weak self] in
            self?.helperInterventionCoordinator.promptForHelperIfNeeded()
        }
    }

    /// 退出前检查主窗口是否有未保存的修改，避免编辑内容被静默丢弃
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewController = mainViewController, viewController.hasUnsavedChanges else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = L10n.tr("main.unsaved.title")
        alert.informativeText = L10n.tr("main.unsaved.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("main.unsaved.discard_and_quit"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        }
        openMainWindow()
        return .terminateCancel
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        remoteProfileAutoRefresher?.stop()
        remoteProfileAutoRefresher = nil
        helperInterventionCoordinator.stopObserving()
        statusItemController = nil
        mainMenuController = nil
        mainWindowController = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        helperInterventionCoordinator.applicationDidBecomeActive()
    }

    /// 显式启用 secure restorable state，避免系统在启动时输出 secure coding 警告。
    /// 具体是否保存/恢复窗口状态，仍由下面两个 delegate 方法统一禁用。
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// 关闭窗口状态恢复，避免 restoreWindowWithIdentifier 报 className=(null)
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        return false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func openPreferencesWindow() {
        preferencesWindowController.showPreferencesWindow()
    }

    @objc private func openGitHubHomepage() {
        UpdateManager.shared.openGitHubHomepage()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        ensureMainWindowController().showWindow(nil)
    }

    @objc func installHelperFromMenu() {
        helperInterventionCoordinator.installHelperFromMenu()
    }

    @objc func uninstallHelperFromMenu() {
        helperInterventionCoordinator.uninstallHelperFromMenu()
    }

    /// 已加载的主界面控制器；窗口尚未创建时返回 nil，不会为此触发窗口加载
    private var mainViewController: ViewController? {
        NSApp.windows.lazy.compactMap { $0.contentViewController as? ViewController }.first
    }

    private func ensureMainWindowController() -> MainWindowController {
        if let mainWindowController {
            return mainWindowController
        }
        let controller = MainWindowController()
        mainWindowController = controller
        return controller
    }

    func loadMainWindowControllerForTesting() {
        ensureMainWindowController().showWindow(nil)
    }

    func closeMainWindowForTesting() {
        ensureMainWindowController().closeWindow()
    }

    var debugMainWindow: NSWindow? {
        ensureMainWindowController().window
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        helperInterventionCoordinator.validateMenuItem(menuItem)
    }
}
