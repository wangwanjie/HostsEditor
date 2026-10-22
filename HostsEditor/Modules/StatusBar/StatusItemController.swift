import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let manager: HostsManager
    private let updateManager: UpdateManager
    private let openMainWindowHandler: () -> Void
    private let openPreferencesHandler: () -> Void
    private var statusMenu: NSMenu?
    private var profileMenuItems: [NSMenuItem] = []
    private var profilesSeparatorItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    init(
        manager: HostsManager,
        updateManager: UpdateManager,
        openMainWindowHandler: @escaping () -> Void,
        openPreferencesHandler: @escaping () -> Void
    ) {
        self.manager = manager
        self.updateManager = updateManager
        self.openMainWindowHandler = openMainWindowHandler
        self.openPreferencesHandler = openPreferencesHandler
        super.init()
        configureStatusItem()
        bind()
    }

    var debugMenuTitles: [String] {
        statusMenu?.items.map(\.title) ?? []
    }

    var debugMenuItems: [NSMenuItem] {
        statusMenu?.items ?? []
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "HostsEditor")
            image?.isTemplate = true
            button.image = image
            button.imageScaling = .scaleProportionallyDown
        }
        rebuildMenu()
    }

    private func bind() {
        manager.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        // 显式指定 target，避免依赖响应链（菜单栏菜单弹出时主窗口可能不在响应链中）
        let openMainWindowItem = NSMenuItem(title: L10n.tr("status.open_main_window"), action: #selector(openMainWindow), keyEquivalent: "")
        openMainWindowItem.target = self
        menu.addItem(openMainWindowItem)
        menu.addItem(NSMenuItem.separator())

        statusMenu = menu
        rebuildProfileMenuItems()

        // 方案列表与后续菜单之间的分隔线；无方案时由 rebuildProfileMenuItems 隐藏
        let separatorItem = NSMenuItem.separator()
        separatorItem.isHidden = profileMenuItems.isEmpty
        menu.addItem(separatorItem)
        profilesSeparatorItem = separatorItem

        let preferencesItem = NSMenuItem(title: L10n.menuPreferences, action: #selector(openPreferences), keyEquivalent: "")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let updatesItem = NSMenuItem(title: L10n.tr("menu.check_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.tr("status.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func rebuildProfileMenuItems() {
        guard let statusMenu else { return }
        for item in profileMenuItems where item.menu === statusMenu {
            statusMenu.removeItem(item)
        }
        profileMenuItems.removeAll()

        var insertIndex = 2
        for profile in manager.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(applyProfileFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.isEnabled ? .on : .off
            statusMenu.insertItem(item, at: insertIndex)
            profileMenuItems.append(item)
            insertIndex += 1
        }
        profilesSeparatorItem?.isHidden = profileMenuItems.isEmpty
    }

    @objc private func openMainWindow() {
        openMainWindowHandler()
    }

    @objc private func applyProfileFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let enabled = sender.state != .on
        Task { @MainActor in
            await manager.setProfileEnabled(id: id, enabled: enabled)
            self.rebuildProfileMenuItems()
        }
    }

    @objc private func openPreferences() {
        openPreferencesHandler()
    }

    @objc private func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusMenu else { return }
        rebuildProfileMenuItems()
    }
}
