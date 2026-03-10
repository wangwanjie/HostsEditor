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
    private var remoteURLField: NSTextField!
    private var addRemoteButton: NSButton!

    /// 左侧选中项：系统（当前 hosts 全文）、默认（仅基底，不含 HostsEditor 块）、或某个方案
    private enum SidebarSelection: Equatable {
        case system
        case base
        case profile(String)
    }

    private var selection: SidebarSelection = .system {
        didSet { syncEditorFromSelection() }
    }

    /// 防止 reloadData 触发 tableViewSelectionDidChange 时误存内容
    private var isUpdatingTable = false

    private let systemRow = 0
    private let baseRow = 1
    private func profileRowIndex(_ index: Int) -> Int { baseRow + 1 + index }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        setupBindings()

        editorTextView.string = manager.currentSystemContent
        editorTextView.setupSyntaxHighlighting()

        Task { @MainActor in
            await manager.refreshSystemContent()
            syncEditorFromSelection()
        }
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

        addProfileButton = NSButton(title: "新建", target: self, action: #selector(addProfile))
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

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(errorLabel)

        let remoteLabel = NSTextField(labelWithString: "远程 URL：")
        remoteLabel.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(remoteLabel)

        remoteURLField = NSTextField()
        remoteURLField.placeholderString = "https://..."
        remoteURLField.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(remoteURLField)

        addRemoteButton = NSButton(title: "添加远程方案", target: self, action: #selector(addRemote))
        addRemoteButton.bezelStyle = .rounded
        addRemoteButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(addRemoteButton)

        refreshRemoteButton = NSButton(title: "刷新远程", target: self, action: #selector(refreshRemote))
        refreshRemoteButton.bezelStyle = .rounded
        refreshRemoteButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(refreshRemoteButton)

        NSLayoutConstraint.activate([
            editorScroll.topAnchor.constraint(equalTo: right.topAnchor, constant: 8),
            editorScroll.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            editorScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -8),
            editorScroll.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -8),
            applyButton.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            refreshButton.leadingAnchor.constraint(equalTo: applyButton.trailingAnchor, constant: 8),
            refreshButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
            applyButton.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -4),
            errorLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor, constant: -8),
            errorLabel.bottomAnchor.constraint(equalTo: remoteLabel.topAnchor, constant: -8),
            remoteLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 8),
            remoteLabel.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -8),
            remoteURLField.leadingAnchor.constraint(equalTo: remoteLabel.trailingAnchor, constant: 8),
            remoteURLField.centerYAnchor.constraint(equalTo: remoteLabel.centerYAnchor),
            remoteURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            addRemoteButton.leadingAnchor.constraint(equalTo: remoteURLField.trailingAnchor, constant: 8),
            addRemoteButton.centerYAnchor.constraint(equalTo: remoteLabel.centerYAnchor),
            refreshRemoteButton.leadingAnchor.constraint(equalTo: addRemoteButton.trailingAnchor, constant: 8),
            refreshRemoteButton.centerYAnchor.constraint(equalTo: remoteLabel.centerYAnchor),
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
        let row: Int
        switch current {
        case .system: row = systemRow
        case .base: row = baseRow
        case .profile(let id):
            if let idx = manager.profiles.firstIndex(where: { $0.id == id }) {
                row = profileRowIndex(idx)
            } else {
                row = systemRow
            }
        }
        profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isUpdatingTable = false
    }

    private func syncEditorFromSelection() {
        switch selection {
        case .system:
            editorTextView.string = manager.currentSystemContent
            editorTextView.isEditable = false
        case .base:
            editorTextView.string = manager.baseSystemContent
            editorTextView.isEditable = false
        case .profile(let id):
            if let p = manager.profile(for: id) {
                editorTextView.string = p.content
                editorTextView.isEditable = true
            }
        }
        editorTextView.setupSyntaxHighlighting()
        editorTextView.breakUndoCoalescing()
        updateButtonsForSelection()
    }

    private func updateButtonsForSelection() {
        let isProfile: Bool
        if case .profile = selection { isProfile = true } else { isProfile = false }
        applyButton.isEnabled = isProfile
        removeProfileButton.isEnabled = isProfile
    }

    // MARK: - Actions

    @objc private func addProfile() {
        let profile = HostsProfile(name: "新方案", content: "")
        manager.addProfile(profile)
        if let idx = manager.profiles.firstIndex(where: { $0.id == profile.id }) {
            let row = profileRowIndex(idx)
            profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selection = .profile(profile.id)
        }
    }

    @objc private func removeProfile() {
        let row = profileTableView.selectedRow
        guard row >= profileRowIndex(0), row < profileRowIndex(manager.profiles.count) else { return }
        let profileIndex = row - (baseRow + 1)
        guard profileIndex >= 0, profileIndex < manager.profiles.count else { return }
        let id = manager.profiles[profileIndex].id
        selection = .system
        Task { await manager.deleteProfile(id: id) }
    }

    /// 将编辑器当前内容保存到选中方案，若方案已启用则立即写入 hosts
    @objc private func saveAndApply() {
        guard case .profile(let id) = selection else { return }
        manager.updateProfile(id: id, content: editorTextView.string)
        Task {
            if manager.profile(for: id)?.isEnabled == true {
                await manager.writeComposedHosts()
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
            syncEditorFromSelection()
        }
    }

    /// 复选框点击 → 切换方案启用状态
    @objc func toggleProfileEnabled(_ sender: NSButton) {
        let row = profileTableView.row(for: sender)
        guard row >= profileRowIndex(0), row < profileRowIndex(manager.profiles.count) else { return }
        let profileIndex = row - (baseRow + 1)
        guard profileIndex >= 0, profileIndex < manager.profiles.count else { return }
        let id = manager.profiles[profileIndex].id
        let enabled = sender.state == .on
        Task { await manager.setProfileEnabled(id: id, enabled: enabled) }
    }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension ViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        2 + manager.profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
        } else {
            let profileIndex = row - (baseRow + 1)
            cell?.configure(with: manager.profiles[profileIndex])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingTable else { return }
        if case .profile(let prevId) = selection {
            manager.updateProfile(id: prevId, content: editorTextView.string)
        }
        let row = profileTableView.selectedRow
        if row == systemRow {
            selection = .system
        } else if row == baseRow {
            selection = .base
        } else if row >= profileRowIndex(0), row < profileRowIndex(manager.profiles.count) {
            let profileIndex = row - (baseRow + 1)
            selection = .profile(manager.profiles[profileIndex].id)
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
