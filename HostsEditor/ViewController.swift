//
//  ViewController.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa
import Combine
import SnapKit

protocol ProfileTableViewContextMenuDelegate: AnyObject {
    func tableView(_ tableView: ProfileTableView, menuForRow row: Int) -> NSMenu?
}

final class ProfileTableView: NSTableView {
    weak var contextMenuDelegate: ProfileTableViewContextMenuDelegate?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        return contextMenuDelegate?.tableView(self, menuForRow: row)
    }
}

class ViewController: NSViewController {

    private static let mainWindowFrameAutosaveName = NSWindow.FrameAutosaveName("HostsEditorMainWindowFrame")

    private let manager = HostsManager.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    private var splitView: NSSplitView!
    private var sidebarScroll: NSScrollView!
    private var profileTableView: ProfileTableView!
    private var editorScroll: NSScrollView!
    private var editorTextView: HostsEditorTextView!
    private var addProfileButton: NSButton!
    private var removeProfileButton: NSButton!
    private var applyButton: NSButton!
    private var refreshButton: NSButton!
    private var refreshRemoteButton: NSButton!
    private var errorLabel: NSTextField!
    private var addRemotePopover: NSPopover?
    private var remoteURLField: NSTextField!
    private var addRemoteConfirmButton: NSButton!
    private var keyMonitor: Any?

    /// 左侧选中项：系统（当前 hosts 全文）、默认（仅基底，不含 HostsEditor 块）、或某个方案
    private enum SidebarSelection: Equatable {
        case system
        case base
        case profile(String)
    }

    private var selection: SidebarSelection = .system {
        didSet { syncEditorFromSelection() }
    }

    /// 上次同步到编辑器时的内容（即已保存到磁盘/方案的内容），用于判断是否有未保存修改
    private var lastSyncedContent: String = ""

    /// 未保存的编辑：切换方案时暂存编辑器内容，再切回来时恢复，避免误以为已保存导致保存按钮不可点
    private var pendingEdits: [String: String] = [:]

    /// 防止 reloadData 触发 tableViewSelectionDidChange 时误存内容
    private var isUpdatingTable = false

    private var localProfiles: [HostsProfile] { manager.profiles.filter { !$0.isRemote } }
    private var remoteProfiles: [HostsProfile] { manager.profiles.filter { $0.isRemote } }

    private let localHeaderRow = 0
    private let systemRow = 1
    private let baseRow = 2
    private func localProfileRow(_ index: Int) -> Int { 3 + index }
    private var remoteHeaderRow: Int { 3 + localProfiles.count }
    private func remoteProfileRow(_ index: Int) -> Int { 3 + localProfiles.count + 1 + index }
    private var totalRows: Int { 4 + localProfiles.count + remoteProfiles.count }

    /// 是否为可选的配置行（非 section header）
    private func isSelectableRow(_ row: Int) -> Bool {
        row != localHeaderRow && row != remoteHeaderRow
    }

    /// 根据行得到选中类型
    private func selection(forRow row: Int) -> SidebarSelection? {
        if row == systemRow { return .system }
        if row == baseRow { return .base }
        if row >= localProfileRow(0), row < localProfileRow(localProfiles.count) {
            let idx = row - 3
            return .profile(localProfiles[idx].id)
        }
        if row >= remoteProfileRow(0), row < remoteProfileRow(remoteProfiles.count) {
            let idx = row - (3 + localProfiles.count + 1)
            return .profile(remoteProfiles[idx].id)
        }
        return nil
    }

    /// 根据当前 selection 得到应选中的行
    private func row(for selection: SidebarSelection) -> Int {
        switch selection {
        case .system: return systemRow
        case .base: return baseRow
        case .profile(let id):
            if let idx = localProfiles.firstIndex(where: { $0.id == id }) { return localProfileRow(idx) }
            if let idx = remoteProfiles.firstIndex(where: { $0.id == id }) { return remoteProfileRow(idx) }
            return systemRow
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        setupBindings()

        editorTextView.string = manager.currentSystemContent
        editorTextView.setupSyntaxHighlighting()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editorTextDidChange),
            name: NSText.didChangeNotification,
            object: editorTextView
        )

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 51, case .profile = self.selection {
                if let fr = self.view.window?.firstResponder as? NSView, fr === self.editorTextView || fr.isDescendant(of: self.editorScroll) {
                    return event
                }
                self.removeProfile()
                return nil
            }
            return event
        }

        Task { @MainActor in
            await manager.refreshSystemContent()
            syncEditorFromSelection()
        }
    }

    @objc private func editorTextDidChange(_ note: Notification) {
        updateButtonsForSelection()
    }

    private var didSetSplitPosition = false
    private var didConfigureWindowFrameAutosave = false

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowIfNeeded()
        if profileTableView.selectedRow < 0 {
            profileTableView.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
            selection = .system
            updateButtonsForSelection()
        }
        DispatchQueue.main.async { [weak self] in
            self?.applySplitPositionIfNeeded()
        }
    }

    private func applySplitPositionIfNeeded() {
        guard !didSetSplitPosition, splitView.subviews.count >= 2, splitView.bounds.width > 300 else { return }
        splitView.setPosition(220, ofDividerAt: 0)
        didSetSplitPosition = true
    }

    private func configureWindowIfNeeded() {
        guard let window = view.window else { return }
        window.minSize = NSSize(width: 800, height: 500)
        guard !didConfigureWindowFrameAutosave else { return }
        didConfigureWindowFrameAutosave = true

        let restored = window.setFrameUsingName(Self.mainWindowFrameAutosaveName)
        _ = window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)
        if !restored {
            window.setContentSize(NSSize(width: 1040, height: 680))
            window.center()
        }
    }

    // MARK: - UI Build

    private func buildUI() {
        view.wantsLayer = true
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addSubview(buildSidebar())
        splitView.addSubview(buildEditorSection())
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        view.addSubview(splitView)
        splitView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Profile"))
        col.title = "方案"
        col.width = 200

        profileTableView = ProfileTableView()
        profileTableView.addTableColumn(col)
        profileTableView.headerView = nil
        profileTableView.rowHeight = 28
        profileTableView.delegate = self
        profileTableView.dataSource = self
        profileTableView.contextMenuDelegate = self
        profileTableView.allowsEmptySelection = true
        profileTableView.allowsMultipleSelection = false
        profileTableView.identifier = NSUserInterfaceItemIdentifier("Profiles")

        sidebarScroll = NSScrollView()
        sidebarScroll.documentView = profileTableView
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebar.addSubview(sidebarScroll)

        addProfileButton = NSButton(title: "新建", target: self, action: #selector(showNewProfileMenu))
        addProfileButton.bezelStyle = .rounded

        removeProfileButton = NSButton(title: "删除", target: self, action: #selector(removeProfile))
        removeProfileButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [addProfileButton, removeProfileButton])
        buttonStack.orientation = .vertical
        buttonStack.alignment = .leading
        buttonStack.spacing = 4
        sidebar.addSubview(buttonStack)

        sidebarScroll.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalTo(buttonStack.snp.top).offset(-8)
        }

        buttonStack.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(8)
            make.trailing.lessThanOrEqualToSuperview().inset(8)
        }
        return sidebar
    }

    private func buildEditorSection() -> NSView {
        let right = NSView()
        right.wantsLayer = true

        editorTextView = HostsEditorTextView()
        editorTextView.isEditable = true
        editorTextView.isRichText = false
        editorTextView.applyEditorFontSize(CGFloat(settings.editorFontSize))
        editorTextView.allowsUndo = true
        editorTextView.minSize = NSSize(width: 200, height: 200)

        editorScroll = NSScrollView()
        editorScroll.documentView = editorTextView
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        right.addSubview(editorScroll)

        applyButton = NSButton(title: "保存并应用", target: self, action: #selector(saveAndApply))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshCurrentHosts))
        refreshButton.bezelStyle = .rounded

        refreshRemoteButton = NSButton(title: "刷新远程", target: self, action: #selector(refreshRemote))
        refreshRemoteButton.bezelStyle = .rounded

        let actionStack = NSStackView(views: [applyButton, refreshButton, refreshRemoteButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 8
        right.addSubview(actionStack)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        right.addSubview(errorLabel)

        editorScroll.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalTo(actionStack.snp.top).offset(-8)
        }

        actionStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.bottom.equalTo(errorLabel.snp.top).offset(-4)
        }

        errorLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.trailing.lessThanOrEqualToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
        }
        return right
    }

    // MARK: - Bindings

    private func setupBindings() {
        manager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadTablePreservingSelection() }
            .store(in: &cancellables)

        manager.$currentSystemContent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard let self, case .system = self.selection else { return }
                self.editorTextView.string = content
                self.lastSyncedContent = content
                self.editorTextView.setupSyntaxHighlighting()
                self.updateButtonsForSelection()
            }
            .store(in: &cancellables)

        manager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.errorLabel.stringValue = msg ?? "" }
            .store(in: &cancellables)

        manager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButtonsForSelection() }
            .store(in: &cancellables)

        settings.$editorFontSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pointSize in
                self?.editorTextView.applyEditorFontSize(CGFloat(pointSize))
            }
            .store(in: &cancellables)
    }

    private func reloadTablePreservingSelection() {
        isUpdatingTable = true
        let current = selection
        profileTableView.reloadData()
        let row = row(for: current)
        if isSelectableRow(row) {
            profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        isUpdatingTable = false
    }

    private func syncEditorFromSelection() {
        switch selection {
        case .system:
            editorTextView.string = manager.currentSystemContent
            editorTextView.isEditable = true
            lastSyncedContent = editorTextView.string
        case .base:
            editorTextView.string = manager.baseSystemContent
            editorTextView.isEditable = false
            lastSyncedContent = editorTextView.string
        case .profile(let id):
            if let p = manager.profile(for: id) {
                let content = pendingEdits[id] ?? p.content
                editorTextView.string = content
                editorTextView.isEditable = !p.isRemote
                lastSyncedContent = p.content
            }
        }
        editorTextView.setupSyntaxHighlighting()
        editorTextView.breakUndoCoalescing()
        updateButtonsForSelection()
    }

    private var isContentDirty: Bool { editorTextView.string != lastSyncedContent }

    private func updateButtonsForSelection() {
        let canSave: Bool
        switch selection { case .system, .profile: canSave = true; case .base: canSave = false }
        applyButton.isEnabled = canSave && isContentDirty && !manager.isLoading
        let isDeletableProfile: Bool
        if case .profile = selection { isDeletableProfile = true } else { isDeletableProfile = false }
        removeProfileButton.isEnabled = isDeletableProfile && !manager.isLoading
        refreshButton.isHidden = selection != .system
        if case .profile(let id) = selection, manager.profile(for: id)?.isRemote == true {
            refreshRemoteButton.isHidden = false
        } else {
            refreshRemoteButton.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func showNewProfileMenu() {
        let menu = NSMenu()
        let localItem = NSMenuItem(title: "本地方案", action: #selector(addLocalProfile), keyEquivalent: "")
        localItem.target = self
        let remoteItem = NSMenuItem(title: "远程方案", action: #selector(showAddRemotePopover), keyEquivalent: "")
        remoteItem.target = self
        menu.addItem(localItem)
        menu.addItem(remoteItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addProfileButton.bounds.height), in: addProfileButton)
    }

    @objc private func addLocalProfile() {
        let profile = HostsProfile(name: "新方案", content: "")
        manager.addProfile(profile)
        selection = .profile(profile.id)
    }

    @objc private func showAddRemotePopover() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 56))
        content.wantsLayer = true

        let label = NSTextField(labelWithString: "远程 URL：")
        content.addSubview(label)

        remoteURLField = NSTextField()
        remoteURLField.placeholderString = "https://..."
        content.addSubview(remoteURLField)

        addRemoteConfirmButton = NSButton(title: "添加", target: self, action: #selector(addRemoteFromPopover))
        addRemoteConfirmButton.bezelStyle = .rounded
        content.addSubview(addRemoteConfirmButton)

        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }

        remoteURLField.snp.makeConstraints { make in
            make.leading.equalTo(label.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.width.equalTo(220)
        }

        addRemoteConfirmButton.snp.makeConstraints { make in
            make.leading.equalTo(remoteURLField.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }

        let popover = NSPopover()
        popover.contentSize = content.frame.size
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = content
        popover.behavior = .transient
        addRemotePopover = popover
        popover.show(relativeTo: addProfileButton.bounds, of: addProfileButton, preferredEdge: .maxY)
        remoteURLField.window?.makeFirstResponder(remoteURLField)
    }

    @objc private func addRemoteFromPopover() {
        let url = remoteURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            manager.setErrorMessage("请输入远程 URL")
            return
        }
        addRemotePopover?.close()
        addRemotePopover = nil
        Task {
            await manager.addRemoteProfile(urlString: url)
            if let p = manager.profiles.first(where: { $0.remoteURL == url }) {
                let row = row(for: .profile(p.id))
                profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                selection = .profile(p.id)
            }
        }
    }

    private func performRemoveProfile() {
        guard case .profile(let id) = selection else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didDelete = await self.manager.deleteProfile(id: id)
            guard didDelete else { return }

            self.pendingEdits.removeValue(forKey: id)
            self.profileTableView.selectRowIndexes(IndexSet(integer: self.systemRow), byExtendingSelection: false)
            self.selection = .system
        }
    }

    @objc private func removeProfile() {
        guard case .profile(let id) = selection else { return }
        let name = manager.profile(for: id)?.name ?? "该方案"
        let alert = NSAlert()
        alert.messageText = "确定要删除「\(name)」吗？"
        alert.informativeText = "删除后无法恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            performRemoveProfile()
        }
    }

    @objc private func toggleProfileEnabledFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = manager.profile(for: id) else { return }
        Task { await manager.setProfileEnabled(id: id, enabled: !profile.isEnabled) }
    }

    @objc private func removeProfileFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let targetRow = row(for: .profile(id))
        guard targetRow >= 0 else { return }
        profileTableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        selection = .profile(id)
        removeProfile()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    /// 将编辑器当前内容保存：系统项直接写 hosts，方案项更新方案并视情况写入
    @objc private func saveAndApply() {
        switch selection {
        case .system:
            Task { await manager.writeSystemContent(editorTextView.string) }
            updateButtonsForSelection()
        case .base:
            break
        case .profile(let id):
            manager.updateProfile(id: id, content: editorTextView.string)
            pendingEdits.removeValue(forKey: id)
            lastSyncedContent = editorTextView.string
            updateButtonsForSelection()
            Task {
                if manager.profile(for: id)?.isEnabled == true {
                    await manager.writeComposedHosts()
                }
            }
        }
    }

    @objc private func addRemote() {
        let url = remoteURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            manager.setErrorMessage("请输入远程 URL")
            return
        }
        Task {
            await manager.addRemoteProfile(urlString: url)
            remoteURLField.stringValue = ""
        }
    }

    /// 刷新：重新从系统读取 hosts，并更新当前编辑器显示
    @objc private func refreshCurrentHosts() {
        Task { [weak self] in
            guard let self else { return }
            await self.manager.refreshSystemContent()
            await MainActor.run {
                self.syncEditorFromSelection()
            }
        }
    }

    @objc private func refreshRemote() {
        guard case .profile(let id) = selection, manager.profile(for: id)?.isRemote == true else {
            manager.setErrorMessage("请先选择远程方案")
            return
        }
        Task {
            await manager.refreshRemoteProfile(id: id)
            await MainActor.run {
                pendingEdits.removeValue(forKey: id)
                syncEditorFromSelection()
            }
        }
    }

    /// 复选框点击 → 切换方案启用状态
    @objc func toggleProfileEnabled(_ sender: NSButton) {
        let row = profileTableView.row(for: sender)
        guard let sel = selection(forRow: row), case .profile(let id) = sel else { return }
        let enabled = sender.state == .on
        Task { await manager.setProfileEnabled(id: id, enabled: enabled) }
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension ViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        totalRows
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == localHeaderRow {
            return makeSectionHeaderCell(title: "本地配置")
        }
        if row == remoteHeaderRow {
            return makeSectionHeaderCell(title: "远程配置")
        }
        let cellId = NSUserInterfaceItemIdentifier("ProfileCell")
        var cell = tableView.makeView(withIdentifier: cellId, owner: self) as? ProfileCellView
        if cell == nil {
            cell = ProfileCellView()
            cell?.identifier = cellId
            cell?.checkbox.target = self
            cell?.checkbox.action = #selector(toggleProfileEnabled(_:))
            cell?.nameField.delegate = self
        }
        if row == systemRow {
            cell?.configureReadOnly(title: "系统")
        } else if row == baseRow {
            cell?.configureReadOnly(title: "默认")
        } else if row >= localProfileRow(0), row < localProfileRow(localProfiles.count) {
            let idx = row - 3
            cell?.configure(with: localProfiles[idx])
        } else if row >= remoteProfileRow(0), row < remoteProfileRow(remoteProfiles.count) {
            let idx = row - (3 + localProfiles.count + 1)
            cell?.configure(with: remoteProfiles[idx])
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        isSelectableRow(row)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingTable else { return }
        if case .profile(let prevId) = selection {
            pendingEdits[prevId] = editorTextView.string
        }
        let row = profileTableView.selectedRow
        if let sel = selection(forRow: row) {
            selection = sel
        }
        updateButtonsForSelection()
    }
}

// MARK: - NSTextFieldDelegate（行内改名）

extension ViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let cell = field.superview as? ProfileCellView,
              let id = cell.profileId else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            field.stringValue = manager.profile(for: id)?.name ?? ""
            return
        }
        // 去掉 isRemote 附加的 ☁ 后缀再保存
        let cleanName = newName.replacingOccurrences(of: " ☁", with: "")
        manager.updateProfile(id: id, name: cleanName)
    }
}

// MARK: - NSSplitViewDelegate

extension ViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? 120 : proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? max(120, splitView.bounds.width - 150) : proposedMaximumPosition
    }
}

extension ViewController: ProfileTableViewContextMenuDelegate {
    func tableView(_ tableView: ProfileTableView, menuForRow row: Int) -> NSMenu? {
        guard let rowSelection = selection(forRow: row),
              case .profile(let id) = rowSelection,
              let profile = manager.profile(for: id) else { return nil }

        if tableView.selectedRow != row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let menu = NSMenu()

        let toggleTitle = profile.isEnabled ? "停用" : "启用"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleProfileEnabledFromContextMenu(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.representedObject = id
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "删除", action: #selector(removeProfileFromContextMenu(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = id
        menu.addItem(deleteItem)

        return menu
    }
}

private extension ViewController {
    func makeSectionHeaderCell(title: String) -> NSTableCellView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        cell.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
        }
        return cell
    }
}
