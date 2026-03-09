//
//  AppDelegate.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var profileMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        buildMainMenu()
        setupStatusBar()
        installHelperIfNeeded()
    }

    /// 用代码构建主菜单，避免 Storyboard 的 systemMenu 导致 “Internal inconsistency in menus”
    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 HostsEditor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "偏好设置…", action: nil, keyEquivalent: ","))
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
        helpMenu.addItem(NSMenuItem(title: "HostsEditor 帮助", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?"))
        let helpItem = NSMenuItem(title: "帮助", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        main.addItem(helpItem)

        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        statusItem = nil
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// 关闭窗口状态恢复，避免 restoreWindowWithIdentifier 报 className=(null)
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        return false
    }

    // MARK: - 帮助程序安装

    private func installHelperIfNeeded() {
        guard !PrivilegedHostsWriter.shared.isHelperInstalled else { return }
        if let err = HostsManager.shared.installHelperIfNeeded() {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要安装帮助程序"
                alert.informativeText = "编辑系统 hosts 需要管理员权限。请点击「安装」并输入密码。\n\n\(err.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "安装")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.installHelperIfNeeded()
                }
            }
        }
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
            item.state = HostsManager.shared.appliedProfileId == profile.id ? .on : .off
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
        Task { @MainActor in
            await HostsManager.shared.applyProfile(id: id)
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
