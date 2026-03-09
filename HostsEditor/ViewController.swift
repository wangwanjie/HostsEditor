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
    private var refreshRemoteButton: NSButton!
    private var errorLabel: NSTextField!
    private var remoteURLField: NSTextField!
    private var addRemoteButton: NSButton!

    private var selectedProfileId: String? {
        didSet { syncEditorFromSelection() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        setupBindings()
        manager.$currentSystemContent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard let self = self, self.selectedProfileId == nil else { return }
                self.editorTextView?.string = content
            }
            .store(in: &cancellables)
        let placeholder = "# 正在加载系统 hosts…"
        editorTextView.string = manager.currentSystemContent.isEmpty ? placeholder : manager.currentSystemContent
        editorTextView.setupSyntaxHighlighting()
        Task { @MainActor in
            await manager.refreshSystemContent()
            if selectedProfileId == nil {
                editorTextView.string = manager.currentSystemContent
                editorTextView.setupSyntaxHighlighting()
            }
        }
    }

    private var didSetSplitPosition = false

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            self?.applySplitPositionIfNeeded()
        }
    }

    private func applySplitPositionIfNeeded() {
        guard !didSetSplitPosition, splitView.subviews.count >= 2, splitView.bounds.width > 300 else { return }
        let sidebarWidth: CGFloat = 220
        splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        didSetSplitPosition = true
    }

    private func buildUI() {
        view.wantsLayer = true

        // 左侧：方案列表
        let sidebar = NSView()
        sidebar.wantsLayer = true
        let profileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Profile"))
        profileColumn.title = "方案"
        profileColumn.width = 180
        profileTableView = NSTableView()
        profileTableView.addTableColumn(profileColumn)
        profileTableView.headerView = nil
        profileTableView.rowHeight = 28
        profileTableView.delegate = self
        profileTableView.dataSource = self
        profileTableView.target = self
        profileTableView.doubleAction = #selector(onDoubleClickProfile)
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

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.delegate = self

        let editorSection = buildEditorSection()
        splitView.addSubview(sidebar)
        splitView.addSubview(editorSection)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            sidebarScroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 8),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            sidebarScroll.bottomAnchor.constraint(equalTo: addProfileButton.topAnchor, constant: -8),
            addProfileButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            addProfileButton.bottomAnchor.constraint(equalTo: removeProfileButton.topAnchor, constant: -4),
            removeProfileButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            removeProfileButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -8),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

        applyButton = NSButton(title: "应用到系统", target: self, action: #selector(applyCurrent))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(applyButton)

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

    private func setupBindings() {
        manager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let currentId = self.selectedProfileId
                self.profileTableView.reloadData()
                if let id = currentId, let idx = self.manager.profiles.firstIndex(where: { $0.id == id }) {
                    self.profileTableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                }
            }
            .store(in: &cancellables)
        manager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in self?.errorLabel.stringValue = msg ?? "" }
            .store(in: &cancellables)
    }

    private func syncEditorFromSelection() {
        if let id = selectedProfileId, let p = manager.profile(for: id) {
            editorTextView.string = p.content
        } else {
            editorTextView.string = manager.currentSystemContent
        }
        editorTextView.breakUndoCoalescing()
    }

    @objc private func onDoubleClickProfile() {
        let row = profileTableView.selectedRow
        guard row >= 0, row < manager.profiles.count else { return }
        let id = manager.profiles[row].id
        Task { await manager.applyProfile(id: id) }
    }

    @objc private func addProfile() {
        let profile = HostsProfile(name: "新方案", content: "")
        manager.addProfile(profile)
        if let idx = manager.profiles.firstIndex(where: { $0.id == profile.id }) {
            profileTableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            selectedProfileId = profile.id
        }
    }

    @objc private func removeProfile() {
        let row = profileTableView.selectedRow
        guard row >= 0, row < manager.profiles.count else { return }
        let id = manager.profiles[row].id
        manager.deleteProfile(id: id)
        selectedProfileId = nil
    }

    @objc private func applyCurrent() {
        let content = editorTextView.string
        let id = selectedProfileId
        Task { await manager.applyContent(content, profileId: id) }
    }

    @objc private func addRemote() {
        let url = remoteURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            manager.setErrorMessage("请输入远程 URL")
            return
        }
        Task {
            await manager.addRemoteProfile(name: "远程: \(URL(string: url)?.host ?? url)", urlString: url)
            remoteURLField.stringValue = ""
        }
    }

    @objc private func refreshRemote() {
        guard let id = selectedProfileId, manager.profile(for: id)?.isRemote == true else {
            manager.setErrorMessage("请先选择远程方案")
            return
        }
        Task { await manager.refreshRemoteProfile(id: id) }
        syncEditorFromSelection()
    }
}

extension ViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        manager.profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("Cell")
        var cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = id
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell?.addSubview(textField)
            cell?.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 6),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cell!.trailingAnchor, constant: -6),
            ])
        }
        let profile = manager.profiles[row]
        var title = profile.name
        if profile.isRemote { title += " ☁" }
        if manager.appliedProfileId == profile.id { title += " ✓" }
        cell?.textField?.stringValue = title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let prevId = selectedProfileId {
            manager.updateProfile(id: prevId, content: editorTextView.string)
        }
        let row = profileTableView.selectedRow
        if row >= 0, row < manager.profiles.count {
            selectedProfileId = manager.profiles[row].id
        } else {
            selectedProfileId = nil
        }
    }
}

extension ViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? 120 : proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? max(120, splitView.bounds.width - 150) : proposedMaximumPosition
    }
}
