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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try AppDatabase.shared.runStartupMigrationIfNeeded()
        } catch {
            NSLog("Business data migration failed: %@", String(describing: error))
        }

        _ = AppSettings.shared

        helperInterventionCoordinator.startObserving()
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
        UpdateManager.shared.scheduleBackgroundUpdateCheck()
        DispatchQueue.main.async { [weak self] in
            self?.helperInterventionCoordinator.promptForHelperIfNeeded()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
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
