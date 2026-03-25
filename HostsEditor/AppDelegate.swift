//
//  AppDelegate.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa
import Combine
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var profileMenuItems: [NSMenuItem] = []
    private let preferencesWindowController = PreferencesWindowController.shared
    private var isPresentingHelperInterventionAlert = false
    private var shouldRetryPendingOperationAfterActivation = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        _ = AppSettings.shared
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHelperInterventionNotification(_:)),
            name: .hostsEditorHelperInterventionRequired,
            object: nil
        )
        bindLocalization()
        buildMainMenu()
        setupStatusBar()
        UpdateManager.shared.configure()
        UpdateManager.shared.scheduleBackgroundUpdateCheck()
        DispatchQueue.main.async { [weak self] in
            self?.promptForHelperIfNeeded()
        }
    }

    /// 用代码构建主菜单，避免 Storyboard 的 systemMenu 导致 “Internal inconsistency in menus”
    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let checkForUpdatesItem = NSMenuItem(title: L10n.tr("menu.check_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: L10n.menuPreferences, action: #selector(openPreferencesWindow), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: L10n.tr("menu.services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.hide_app"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.hide_others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.show_all"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.quit_app"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileMenu = NSMenu(title: L10n.tr("menu.file"))
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.new"), action: nil, keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.open"), action: nil, keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(title: L10n.tr("menu.file"), action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editMenu = NSMenu(title: L10n.tr("menu.edit"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.delete"), action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.find"), action: #selector(ViewController.showFindBar(_:)), keyEquivalent: "f"))
        editMenu.addItem(NSMenuItem(title: L10n.tr("menu.replace"), action: #selector(ViewController.showReplaceBar(_:)), keyEquivalent: "r"))
        let toggleCommentItem = NSMenuItem(title: L10n.tr("menu.toggle_comment"), action: #selector(ViewController.toggleCommentSelection(_:)), keyEquivalent: "/")
        toggleCommentItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(toggleCommentItem)
        editMenu.addItem(NSMenuItem.separator())
        let enlargeTextItem = NSMenuItem(title: L10n.tr("menu.increase_font"), action: #selector(ViewController.makeTextLarger(_:)), keyEquivalent: "+")
        enlargeTextItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(enlargeTextItem)
        let shrinkTextItem = NSMenuItem(title: L10n.tr("menu.decrease_font"), action: #selector(ViewController.makeTextSmaller(_:)), keyEquivalent: "-")
        shrinkTextItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(shrinkTextItem)
        let editItem = NSMenuItem(title: L10n.tr("menu.edit"), action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: L10n.tr("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L10n.tr("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L10n.tr("menu.zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu
        let windowItem = NSMenuItem(title: L10n.tr("menu.window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        let helpMenu = NSMenu(title: L10n.tr("menu.help"))
        let helpItem = NSMenuItem(title: L10n.tr("menu.help_hosts_editor"), action: #selector(openGitHubHomepage), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)
        helpMenu.addItem(NSMenuItem.separator())
        let installHelperItem = NSMenuItem(title: L10n.preferencesRepairHelper, action: #selector(installHelperFromMenu), keyEquivalent: "")
        installHelperItem.target = self
        helpMenu.addItem(installHelperItem)
        let uninstallHelperItem = NSMenuItem(title: L10n.preferencesDisableHelper, action: #selector(uninstallHelperFromMenu), keyEquivalent: "")
        uninstallHelperItem.target = self
        helpMenu.addItem(uninstallHelperItem)
        let helpMenuItem = NSMenuItem(title: L10n.tr("menu.help"), action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        main.addItem(helpMenuItem)

        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        NotificationCenter.default.removeObserver(self)
        statusItem = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard shouldRetryPendingOperationAfterActivation else { return }

        switch PrivilegedHostsWriter.shared.daemonStatus {
        case .enabled:
            shouldRetryPendingOperationAfterActivation = false
            Task { @MainActor in
                await HostsManager.shared.retryPendingPrivilegedOperationIfNeeded()
            }
        case .requiresApproval:
            return
        case .notRegistered, .notFound:
            shouldRetryPendingOperationAfterActivation = false
        @unknown default:
            shouldRetryPendingOperationAfterActivation = false
        }
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

    // MARK: - 帮助程序安装

    private func promptForHelperIfNeeded() {
        if HostsManager.shared.isHelperExplicitlyDisabled {
            return
        }

        switch PrivilegedHostsWriter.shared.daemonStatus {
        case .enabled:
            return
        case .notRegistered, .notFound:
            presentHelperInstallAlert(operation: nil)
        case .requiresApproval:
            presentHelperApprovalAlert(operation: nil)
        @unknown default:
            return
        }
    }

    private func presentHelperInstallAlert(operation: String?) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.install.title")
        if let operation {
            alert.informativeText = L10n.tr("helper.alert.install.operation_message", operation)
        } else {
            alert.informativeText = L10n.tr("helper.alert.install.message")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.enable_now"))
        alert.addButton(withTitle: L10n.tr("common.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            performHelperSetup(
                forceRepair: false,
                announceSuccess: false,
                retryPendingOperation: operation != nil
            )
        }
    }

    private func presentHelperApprovalAlert(operation: String?) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.approval.title")
        if let operation {
            alert.informativeText = L10n.tr("helper.alert.approval.operation_message", operation)
        } else {
            alert.informativeText = L10n.tr("helper.alert.approval.message")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.open_system_settings"))
        alert.addButton(withTitle: L10n.tr("common.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            shouldRetryPendingOperationAfterActivation = operation != nil
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func showHelperInstallError(_ err: Error) {
        let alert = NSAlert()
        if let privilegedError = err as? PrivilegedHostsError {
            switch privilegedError {
            case .registrationFailed(let message):
                alert.messageText = L10n.tr("helper.alert.enable_failed.title")
                alert.informativeText = message
            case .repairRequired(let message):
                alert.messageText = L10n.tr("helper.alert.repair_required.title")
                alert.informativeText = message
            default:
                alert.messageText = L10n.tr("helper.alert.enable_failed.title")
                alert.informativeText = err.localizedDescription
            }
        } else {
            alert.messageText = L10n.tr("helper.alert.enable_failed.title")
            alert.informativeText = err.localizedDescription
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    private func performHelperSetup(forceRepair: Bool, announceSuccess: Bool, retryPendingOperation: Bool = false) {
        Task { @MainActor in
            do {
                if forceRepair {
                    try await HostsManager.shared.reinstallHelper()
                } else {
                    try await HostsManager.shared.enableHelper()
                }

                if retryPendingOperation {
                    await HostsManager.shared.retryPendingPrivilegedOperationIfNeeded()
                }

                guard announceSuccess else { return }
                let alert = NSAlert()
                alert.messageText = L10n.tr("helper.alert.ready.title")
                alert.informativeText = L10n.tr("helper.alert.ready.message")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.tr("common.ok"))
                alert.runModal()
            } catch let privilegedError as PrivilegedHostsError {
                switch privilegedError {
                case .requiresApproval:
                    presentHelperApprovalAlert(operation: nil)
                case .disabledByUser, .registrationFailed, .repairRequired, .connectionFailed, .timeout:
                    showHelperInstallError(privilegedError)
                }
            } catch {
                showHelperInstallError(error)
            }
        }
    }

    @objc private func installHelperFromMenu() {
        performHelperSetup(forceRepair: true, announceSuccess: true)
    }

    @objc private func uninstallHelperFromMenu() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.disable.title")
        alert.informativeText = L10n.tr("helper.alert.disable.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.disable"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await HostsManager.shared.uninstallHelperAndWait()
                let success = NSAlert()
                success.messageText = L10n.tr("helper.alert.disabled_done.title")
                success.informativeText = L10n.tr("helper.alert.disabled_done.message")
                success.alertStyle = .informational
                success.addButton(withTitle: L10n.tr("common.ok"))
                success.runModal()
            } catch {
                let failure = NSAlert()
                failure.messageText = L10n.tr("helper.alert.disable_failed.title")
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: L10n.tr("common.ok"))
                failure.runModal()
            }
        }
    }

    @objc private func handleHelperInterventionNotification(_ notification: Notification) {
        guard !isPresentingHelperInterventionAlert,
              let kindRawValue = notification.userInfo?["kind"] as? String,
              let kind = HelperInterventionKind(rawValue: kindRawValue),
              let operation = notification.userInfo?["operation"] as? String else { return }

        isPresentingHelperInterventionAlert = true
        defer { isPresentingHelperInterventionAlert = false }

        NSApp.activate(ignoringOtherApps: true)

        switch kind {
        case .install:
            if HostsManager.shared.isHelperExplicitlyDisabled {
                let alert = NSAlert()
                alert.messageText = L10n.tr("helper.alert.disabled.title")
                alert.informativeText = L10n.tr("helper.alert.disabled.operation_message", operation)
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.tr("common.enable_now"))
                alert.addButton(withTitle: L10n.tr("common.cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    performHelperSetup(forceRepair: false, announceSuccess: false, retryPendingOperation: true)
                }
            } else {
                presentHelperInstallAlert(operation: operation)
            }
        case .approval:
            presentHelperApprovalAlert(operation: operation)
        case .repair:
            let alert = NSAlert()
            alert.messageText = L10n.tr("helper.alert.repair.title")
            alert.informativeText = L10n.tr("helper.alert.repair.message", operation)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.tr("common.repair_now"))
            alert.addButton(withTitle: L10n.tr("common.later"))
            if alert.runModal() == .alertFirstButtonReturn {
                performHelperSetup(forceRepair: true, announceSuccess: false, retryPendingOperation: true)
            }
        }
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

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "HostsEditor")
            image?.isTemplate = true
            button.image = image
            button.imageScaling = .scaleProportionallyDown
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        statusMenu = NSMenu()
        profileMenuItems.removeAll()
        statusMenu?.addItem(NSMenuItem(title: L10n.tr("status.open_main_window"), action: #selector(openMainWindow), keyEquivalent: ""))
        statusMenu?.addItem(NSMenuItem.separator())
        rebuildProfileMenuItems()
        statusMenu?.addItem(NSMenuItem.separator())
        statusMenu?.addItem(NSMenuItem(title: L10n.tr("status.quit"), action: #selector(quit), keyEquivalent: "q"))
        statusMenu?.delegate = self
        statusItem?.menu = statusMenu
    }

    private func rebuildProfileMenuItems() {
        for item in profileMenuItems where item.menu === statusMenu {
            statusMenu?.removeItem(item)
        }
        profileMenuItems = []
        var insertIndex = 2
        for profile in HostsManager.shared.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(applyProfileFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.isEnabled ? .on : .off
            statusMenu?.insertItem(item, at: insertIndex)
            profileMenuItems.append(item)
            insertIndex += 1
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        if NSApp.windows.first(where: { $0.canBecomeMain }) == nil {
            // 若没有窗口则从 storyboard 打开
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            guard let wc = storyboard.instantiateController(withIdentifier: "WindowController") as? NSWindowController else { return }
            wc.showWindow(nil)
        }
    }

    @objc private func applyProfileFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let enabled = sender.state != .on   // 切换启用状态
        Task { @MainActor in
            await HostsManager.shared.setProfileEnabled(id: id, enabled: enabled)
            rebuildProfileMenuItems()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func bindLocalization() {
        guard cancellables.isEmpty else { return }
        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildMainMenu()
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == statusMenu { rebuildProfileMenuItems() }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(installHelperFromMenu):
            return true
        case #selector(uninstallHelperFromMenu):
            return HostsManager.shared.hasRegisteredHelper
        default:
            return true
        }
    }
}
