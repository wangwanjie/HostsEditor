import AppKit
import Combine

@MainActor
final class MainMenuController: NSObject {
    private let openPreferencesHandler: () -> Void
    private let installHelperHandler: () -> Void
    private let uninstallHelperHandler: () -> Void
    private let checkForUpdatesHandler: () -> Void
    private let openHelpHandler: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        openPreferencesHandler: @escaping () -> Void,
        installHelperHandler: @escaping () -> Void,
        uninstallHelperHandler: @escaping () -> Void,
        checkForUpdatesHandler: @escaping () -> Void,
        openHelpHandler: @escaping () -> Void
    ) {
        self.openPreferencesHandler = openPreferencesHandler
        self.installHelperHandler = installHelperHandler
        self.uninstallHelperHandler = uninstallHelperHandler
        self.checkForUpdatesHandler = checkForUpdatesHandler
        self.openHelpHandler = openHelpHandler
        super.init()
        install()
        bindLocalization()
    }

    func install() {
        NSApp.mainMenu = buildMainMenu()
    }

    private func bindLocalization() {
        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.install()
            }
            .store(in: &cancellables)
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        main.addItem(makeAppMenuItem())
        main.addItem(makeFileMenuItem())
        main.addItem(makeEditMenuItem())
        main.addItem(makeWindowMenuItem())
        main.addItem(makeHelpMenuItem())
        return main
    }

    private func makeAppMenuItem() -> NSMenuItem {
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
        return appItem
    }

    private func makeFileMenuItem() -> NSMenuItem {
        let fileMenu = NSMenu(title: L10n.tr("menu.file"))
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.new"), action: nil, keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.open"), action: nil, keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: L10n.tr("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let fileItem = NSMenuItem(title: L10n.tr("menu.file"), action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        return fileItem
    }

    private func makeEditMenuItem() -> NSMenuItem {
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
        return editItem
    }

    private func makeWindowMenuItem() -> NSMenuItem {
        let windowMenu = NSMenu(title: L10n.tr("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L10n.tr("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L10n.tr("menu.zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu

        let windowItem = NSMenuItem(title: L10n.tr("menu.window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        return windowItem
    }

    private func makeHelpMenuItem() -> NSMenuItem {
        let helpMenu = NSMenu(title: L10n.tr("menu.help"))

        let helpItem = NSMenuItem(title: L10n.tr("menu.help_hosts_editor"), action: #selector(openHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)
        helpMenu.addItem(NSMenuItem.separator())

        let installHelperItem = NSMenuItem(title: L10n.preferencesRepairHelper, action: #selector(installHelper), keyEquivalent: "")
        installHelperItem.target = self
        helpMenu.addItem(installHelperItem)

        let uninstallHelperItem = NSMenuItem(title: L10n.preferencesDisableHelper, action: #selector(uninstallHelper), keyEquivalent: "")
        uninstallHelperItem.target = self
        helpMenu.addItem(uninstallHelperItem)

        let helpMenuItem = NSMenuItem(title: L10n.tr("menu.help"), action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        return helpMenuItem
    }

    @objc private func openPreferencesWindow() {
        openPreferencesHandler()
    }

    @objc private func installHelper() {
        installHelperHandler()
    }

    @objc private func uninstallHelper() {
        uninstallHelperHandler()
    }

    @objc private func checkForUpdates() {
        checkForUpdatesHandler()
    }

    @objc private func openHelp() {
        openHelpHandler()
    }
}
