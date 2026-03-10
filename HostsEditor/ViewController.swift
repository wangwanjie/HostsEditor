//
//  ViewController.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa
import Combine

class ViewController: NSViewController {

    private let manager = HostsManager.shared
    private var cancellables = Set<AnyCancellable>()

    private var splitView: NSSplitView!
    private var sidebarScroll: NSScrollView!
    private var profileTableView: NSTableView!
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

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.minSize = NSSize(width: 800, height: 500)
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

    // MARK: - UI Build

    private func buildUI() {
        view.wantsLayer = true
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.delegate = self
        splitView.addSubview(buildSidebar())
        splitView.addSubview(buildEditorSection())
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        view.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Profile"))
        col.title = "方案"
        col.width = 200

        profileTableView = NSTableView()
        profileTableView.addTableColumn(col)
        profileTableView.headerView = nil
        profileTableView.rowHeight = 28
        profileTableView.delegate = self
        profileTableView.dataSource = self
        profileTableView.allowsEmptySelection = true
        profileTableView.allowsMultipleSelection = false
        profileTableView.identifier = NSUserInterfaceItemIdentifier("Profiles")

        sidebarScroll = NSScrollView()
        sidebarScroll.documentView = profileTableView
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarScroll)

        addProfileButton = NSButton(title: "新建", target: self, action: #selector(showNewProfileMenu))
        addProfileButton.bezelStyle = .rounded
        addProfileButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(addProfileButton)

        removeProfileButton = NSButton(title: "删除", target: self, action: #selector(removeProfile))
        removeProfileButton.bezelStyle = .rounded
        removeProfileButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(removeProfileButton)

        NSLayoutConstraint.activate([
            sidebarScroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            sidebarScroll.bottomAnchor.constraint(equalTo: addProfileButton.topAnchor, constant: -8),
            addProfileButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addProfileButton.bottomAnchor.constraint(equalTo: removeProfileButton.topAnchor, constant: -4),
            removeProfileButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            removeProfileButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -8),
        ])
        return sidebar
    }

    private func buildEditorSection() -> NSView {
        let right = NSView()
        right.wantsLayer = true

        editorTextView = HostsEditorTextView()
        editorTextView.isEditable = true
        editorTextView.isRichText = false
        editorTextView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        editorTextView.allowsUndo = true
        editorTextView.minSize = NSSize(width: 200, height: 200)

        editorScroll = NSScrollView()
        editorScroll.documentView = editorTextView
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(editorScroll)

        applyButton = NSButton(title: "保存并应用", target: self, action: #selector(saveAndApply))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(applyButton)

        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshCurrentHosts))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(refreshButton)

        refreshRemoteButton = NSButton(title: "刷新远程", target: self, action: #selector(refreshRemote))
        refreshRemoteButton.bezelStyle = .rounded
        refreshRemoteButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(refreshRemoteButton)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            editorScroll.topAnchor.constraint(equalTo: right.topAnchor, constant: 8),
            editorScroll.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            editorScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -8),
            editorScroll.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -8),
            applyButton.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            applyButton.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -4),
            refreshButton.leadingAnchor.constraint(equalTo: applyButton.trailingAnchor, constant: 8),
            refreshButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            refreshRemoteButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            refreshRemoteButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor, constant: -8),
            errorLabel.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -8),
        ])
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
                self.editorTextView.setupSyntaxHighlighting()
            }
            .store(in: &cancellables)

        manager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.errorLabel.stringValue = msg ?? "" }
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
        applyButton.isEnabled = canSave && isContentDirty
        let isDeletableProfile: Bool
        if case .profile = selection { isDeletableProfile = true } else { isDeletableProfile = false }
        removeProfileButton.isEnabled = isDeletableProfile
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
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 56))
        content.wantsLayer = true

        let label = NSTextField(labelWithString: "远程 URL：")
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)

        remoteURLField = NSTextField()
        remoteURLField.placeholderString = "https://..."
        remoteURLField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(remoteURLField)

        addRemoteConfirmButton = NSButton(title: "添加", target: self, action: #selector(addRemoteFromPopover))
        addRemoteConfirmButton.bezelStyle = .rounded
        addRemoteConfirmButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(addRemoteConfirmButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            remoteURLField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            remoteURLField.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            remoteURLField.widthAnchor.constraint(equalToConstant: 220),
            addRemoteConfirmButton.leadingAnchor.constraint(equalTo: remoteURLField.trailingAnchor, constant: 8),
            addRemoteConfirmButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            addRemoteConfirmButton.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
        ])

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
        pendingEdits.removeValue(forKey: id)
        selection = .system
        Task { await manager.deleteProfile(id: id) }
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

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    /// 将编辑器当前内容保存：系统项直接写 hosts，方案项更新方案并视情况写入
    @objc private func saveAndApply() {
        switch selection {
        case .system:
            lastSyncedContent = editorTextView.string
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
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "本地配置")
            label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        if row == remoteHeaderRow {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "远程配置")
            label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
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
