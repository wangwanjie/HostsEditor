//
//  AppDelegate.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var profileMenuItems: [NSMenuItem] = []
    private let preferencesWindowController = PreferencesWindowController.shared
    private var isPresentingHelperInterventionAlert = false
    private var shouldRetryPendingOperationAfterActivation = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHelperInterventionNotification(_:)),
            name: .hostsEditorHelperInterventionRequired,
            object: nil
        )
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
        appMenu.addItem(NSMenuItem(title: "关于 HostsEditor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let checkForUpdatesItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: "偏好设置…", action: #selector(openPreferencesWindow), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 HostsEditor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 HostsEditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(NSMenuItem(title: "新建", action: nil, keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "打开…", action: nil, keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        let helpMenu = NSMenu(title: "帮助")
        let helpItem = NSMenuItem(title: "HostsEditor 帮助", action: #selector(openGitHubHomepage), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)
        helpMenu.addItem(NSMenuItem.separator())
        let installHelperItem = NSMenuItem(title: "启用或修复后台帮助程序", action: #selector(installHelperFromMenu), keyEquivalent: "")
        installHelperItem.target = self
        helpMenu.addItem(installHelperItem)
        let uninstallHelperItem = NSMenuItem(title: "停用后台帮助程序", action: #selector(uninstallHelperFromMenu), keyEquivalent: "")
        uninstallHelperItem.target = self
        helpMenu.addItem(uninstallHelperItem)
        let helpMenuItem = NSMenuItem(title: "帮助", action: nil, keyEquivalent: "")
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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// 关闭窗口状态恢复，避免 restoreWindowWithIdentifier 报 className=(null)
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
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
        alert.messageText = operation == nil ? "需要启用后台帮助程序" : "需要启用后台帮助程序"
        if let operation {
            alert.informativeText = "要\(operation)，需要先启用 HostsEditor 的后台帮助程序。首次启用后，macOS 可能要求你在“系统设置 -> 通用 -> 登录项与扩展程序”里允许它运行。"
        } else {
            alert.informativeText = "HostsEditor 需要启用后台帮助程序才能写入 /etc/hosts。首次启用后，macOS 可能要求你在“系统设置 -> 通用 -> 登录项与扩展程序”里允许它运行。"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即启用")
        alert.addButton(withTitle: "稍后")
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
        alert.messageText = "需要允许后台帮助程序"
        if let operation {
            alert.informativeText = "要\(operation)，请前往“系统设置 -> 通用 -> 登录项与扩展程序”允许 HostsEditor 的后台帮助程序。开启后返回应用即可继续，无需再次授权。"
        } else {
            alert.informativeText = "请前往“系统设置 -> 通用 -> 登录项与扩展程序”允许 HostsEditor 的后台帮助程序。开启后返回应用即可继续写入或读取 hosts，无需再次授权。"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
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
                alert.messageText = "启用后台帮助程序失败"
                alert.informativeText = message
            case .repairRequired(let message):
                alert.messageText = "后台帮助程序需要修复"
                alert.informativeText = message
            default:
                alert.messageText = "启用后台帮助程序失败"
                alert.informativeText = err.localizedDescription
            }
        } else {
            alert.messageText = "启用后台帮助程序失败"
            alert.informativeText = err.localizedDescription
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
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
                alert.messageText = "后台帮助程序已就绪"
                alert.informativeText = "现在可以继续写入系统 hosts 文件。后续只要该后台帮助程序保持允许状态，就不需要再次授权。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
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
        alert.messageText = "停用后台帮助程序"
        alert.informativeText = "停用后将无法直接写入系统 hosts，直到重新启用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await HostsManager.shared.uninstallHelperAndWait()
                let success = NSAlert()
                success.messageText = "后台帮助程序已停用"
                success.informativeText = "如需继续编辑系统 hosts，可在“帮助”菜单中重新启用。"
                success.alertStyle = .informational
                success.addButton(withTitle: "确定")
                success.runModal()
            } catch {
                let failure = NSAlert()
                failure.messageText = "停用后台帮助程序失败"
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: "确定")
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
                alert.messageText = "后台帮助程序已停用"
                alert.informativeText = "要\(operation)，请先在“帮助”菜单中重新启用后台帮助程序。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "重新启用")
                alert.addButton(withTitle: "取消")
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
            alert.messageText = "需要修复后台帮助程序"
            alert.informativeText = "要\(operation)，HostsEditor 需要重新注册后台帮助程序。全新安装并已允许后，后续读写 hosts 不应再次授权；如果你之前装过旧版本，请先清理旧登录项或后台任务记录后再修复。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "立即修复")
            alert.addButton(withTitle: "稍后")
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
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Hosts")
        }
        statusMenu = NSMenu()
        statusMenu?.addItem(NSMenuItem(title: "打开 HostsEditor", action: #selector(openMainWindow), keyEquivalent: ""))
        statusMenu?.addItem(NSMenuItem.separator())
        rebuildProfileMenuItems()
        statusMenu?.addItem(NSMenuItem.separator())
        statusMenu?.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusMenu?.delegate = self
        statusItem?.menu = statusMenu
    }

    private func rebuildProfileMenuItems() {
        profileMenuItems.forEach { statusMenu?.removeItem($0) }
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
