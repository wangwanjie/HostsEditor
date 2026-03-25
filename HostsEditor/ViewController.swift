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

    private let manager: HostsManager
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    private var splitView: NSSplitView!
    private var sidebarScroll: NSScrollView!
    private var sidebarColumn: NSTableColumn!
    private var profileTableView: ProfileTableView!
    private var editorScroll: NSScrollView!
    private var editorTextView: HostsEditorTextView!
    private var findBarView: EditorFindBarView!
    private var addProfileButton: NSButton!
    private var removeProfileButton: NSButton!
    private var applyButton: NSButton!
    private var refreshButton: NSButton!
    private var refreshRemoteButton: NSButton!
    private var errorLabel: NSTextField!
    private var addRemotePopover: NSPopover?
    private var remoteURLLabel: NSTextField?
    private var remoteURLField: NSTextField!
    private var addRemoteConfirmButton: NSButton!
    private var keyMonitor: Any?
    private var didApplyInitialSidebarWidth = false
    private var isApplyingStoredSidebarWidth = false
    private var isReplaceBarExpanded = false
    private var findMatches: [NSRange] = []
    private var currentFindMatchIndex: Int?

    @MainActor
    init(manager: HostsManager? = nil, settings: AppSettings? = nil) {
        self.manager = manager ?? .shared
        self.settings = settings ?? .shared
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor
    required init?(coder: NSCoder) {
        manager = .shared
        settings = .shared
        super.init(coder: coder)
    }

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
    private var isFindBarVisible: Bool { findBarView != nil && !findBarView.isHidden }
    private var currentFindRange: NSRange? {
        guard let currentFindMatchIndex, findMatches.indices.contains(currentFindMatchIndex) else { return nil }
        return findMatches[currentFindMatchIndex]
    }
    private var canEditCurrentSelection: Bool {
        switch selection {
        case .system:
            return true
        case .base:
            return false
        case .profile(let id):
            return manager.profile(for: id)?.isRemote != true
        }
    }

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
        applyLocalization()
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
                if Self.isEditingTextInput(
                    responder: self.view.window?.firstResponder,
                    editorTextView: self.editorTextView,
                    editorContainerView: self.editorScroll
                ) {
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

    override func viewWillAppear() {
        super.viewWillAppear()
        configureWindowIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyStoredSidebarWidthIfNeeded()
        if profileTableView.selectedRow < 0 {
            profileTableView.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
            selection = .system
            updateButtonsForSelection()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyStoredSidebarWidthIfNeeded()
        syncProfileColumnWidth()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Menu Actions

    @objc func makeTextLarger(_ sender: Any?) {
        settings.adjustEditorFontSize(by: AppSettings.editorFontSizeStep)
    }

    @objc func makeTextSmaller(_ sender: Any?) {
        settings.adjustEditorFontSize(by: -AppSettings.editorFontSizeStep)
    }

    @objc func showFindBar(_ sender: Any?) {
        presentFindBar(showReplace: false, focusReplaceField: false)
    }

    @objc func showReplaceBar(_ sender: Any?) {
        presentFindBar(showReplace: canEditCurrentSelection, focusReplaceField: canEditCurrentSelection)
    }

    @objc func toggleCommentSelection(_ sender: Any?) {
        guard canEditCurrentSelection else { return }
        let result = HostsEditorTextEditing.toggleComments(
            in: editorTextView.string,
            selectedRanges: editorTextView.selectedNSRanges
        )
        applyEditorMutation(result)
    }

    // MARK: - Window Configuration

    private var didConfigureWindowFrameAutosave = false

    private func configureWindowIfNeeded() {
        guard let window = view.window else { return }
        window.isRestorable = false
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
        let sidebarWidth = CGFloat(settings.sidebarWidth)
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: max(view.bounds.height, 320)))
        sidebar.wantsLayer = true

        sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Profile"))
        sidebarColumn.title = L10n.mainProfiles
        sidebarColumn.width = max(180, sidebarWidth - 20)
        sidebarColumn.resizingMask = .autoresizingMask

        profileTableView = ProfileTableView()
        profileTableView.addTableColumn(sidebarColumn)
        profileTableView.headerView = nil
        profileTableView.rowHeight = 28
        profileTableView.delegate = self
        profileTableView.dataSource = self
        profileTableView.contextMenuDelegate = self
        profileTableView.allowsEmptySelection = true
        profileTableView.allowsMultipleSelection = false
        profileTableView.identifier = NSUserInterfaceItemIdentifier("Profiles")
        profileTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        sidebarScroll = NSScrollView()
        sidebarScroll.documentView = profileTableView
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebar.addSubview(sidebarScroll)

        addProfileButton = NSButton(title: L10n.mainAdd, target: self, action: #selector(showNewProfileMenu))
        addProfileButton.bezelStyle = .rounded
        sidebar.addSubview(addProfileButton)

        removeProfileButton = NSButton(title: L10n.mainDelete, target: self, action: #selector(removeProfile))
        removeProfileButton.bezelStyle = .rounded
        sidebar.addSubview(removeProfileButton)

        sidebarScroll.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalTo(addProfileButton.snp.top).offset(-8)
        }

        addProfileButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.bottom.equalTo(removeProfileButton.snp.top).offset(-4)
        }

        removeProfileButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
        }
        return sidebar
    }

    private func buildEditorSection() -> NSView {
        let right = NSView(frame: NSRect(x: 0, y: 0, width: max(view.bounds.width - CGFloat(settings.sidebarWidth), 320), height: max(view.bounds.height, 320)))
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

        findBarView = EditorFindBarView()
        findBarView.isHidden = true
        findBarView.findField.delegate = self
        findBarView.replaceField.delegate = self
        findBarView.previousButton.target = self
        findBarView.previousButton.action = #selector(findPreviousMatch(_:))
        findBarView.nextButton.target = self
        findBarView.nextButton.action = #selector(findNextMatch(_:))
        findBarView.replaceToggleButton.target = self
        findBarView.replaceToggleButton.action = #selector(toggleReplacePanel(_:))
        findBarView.replaceButton.target = self
        findBarView.replaceButton.action = #selector(replaceCurrentMatch(_:))
        findBarView.replaceAllButton.target = self
        findBarView.replaceAllButton.action = #selector(replaceAllMatches(_:))
        findBarView.closeButton.target = self
        findBarView.closeButton.action = #selector(closeFindBar(_:))
        right.addSubview(findBarView)

        applyButton = NSButton(title: L10n.mainSaveAndApply, target: self, action: #selector(saveAndApply))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        right.addSubview(applyButton)

        refreshButton = NSButton(title: L10n.mainRefresh, target: self, action: #selector(refreshCurrentHosts))
        refreshButton.bezelStyle = .rounded
        right.addSubview(refreshButton)

        refreshRemoteButton = NSButton(title: L10n.mainRefreshRemote, target: self, action: #selector(refreshRemote))
        refreshRemoteButton.bezelStyle = .rounded
        right.addSubview(refreshRemoteButton)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        right.addSubview(errorLabel)

        editorScroll.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalTo(applyButton.snp.top).offset(-8)
        }

        findBarView.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(12)
            make.leading.greaterThanOrEqualToSuperview().inset(12)
            make.width.lessThanOrEqualTo(420)
            make.width.equalTo(420).priority(.high)
        }

        applyButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.bottom.equalTo(errorLabel.snp.top).offset(-4)
        }

        refreshButton.snp.makeConstraints { make in
            make.leading.equalTo(applyButton.snp.trailing).offset(8)
            make.centerY.equalTo(applyButton)
        }

        refreshRemoteButton.snp.makeConstraints { make in
            make.leading.equalTo(refreshButton.snp.trailing).offset(8)
            make.centerY.equalTo(applyButton)
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
            .sink { [weak self] _ in
                self?.reloadTablePreservingSelection()
                self?.refreshEditorForCurrentSelectionAfterProfilesChange()
                self?.updateButtonsForSelection()
            }
            .store(in: &cancellables)

        manager.$currentSystemContent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                guard let self, case .system = self.selection else { return }
                self.editorTextView.string = content
                self.lastSyncedContent = content
                self.editorTextView.setupSyntaxHighlighting()
                self.refreshFindResults(scrollToCurrent: false)
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

        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLocalization()
            }
            .store(in: &cancellables)
    }

    private func applyLocalization() {
        guard sidebarColumn != nil else { return }
        sidebarColumn.title = L10n.mainProfiles
        addProfileButton.title = L10n.mainAdd
        removeProfileButton.title = L10n.mainDelete
        applyButton.title = L10n.mainSaveAndApply
        refreshButton.title = L10n.mainRefresh
        refreshRemoteButton.title = L10n.mainRefreshRemote
        findBarView.applyLocalization()
        remoteURLLabel?.stringValue = L10n.mainRemoteURL
        remoteURLField?.placeholderString = L10n.mainRemoteURLPlaceholder
        addRemoteConfirmButton?.title = L10n.mainAddRemoteConfirm
        profileTableView?.reloadData()
    }

    private func reloadTablePreservingSelection() {
        isUpdatingTable = true
        let current = selection
        profileTableView.reloadData()
        let row = row(for: current)
        if isSelectableRow(row) {
            profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        syncProfileColumnWidth()
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

        if !canEditCurrentSelection {
            isReplaceBarExpanded = false
        }

        editorTextView.setupSyntaxHighlighting()
        editorTextView.breakUndoCoalescing()
        refreshFindResults(scrollToCurrent: false)
        updateButtonsForSelection()
    }

    private func refreshEditorForCurrentSelectionAfterProfilesChange() {
        guard case .profile(let id) = selection else { return }

        guard let profile = manager.profile(for: id) else {
            pendingEdits.removeValue(forKey: id)
            selection = .system
            profileTableView?.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
            return
        }

        let expectedEditorContent = pendingEdits[id] ?? profile.content
        guard editorTextView.string != expectedEditorContent || lastSyncedContent != profile.content else { return }

        syncEditorFromSelection()
        editorTextView.rehighlightEntireDocument()
    }

    private var isContentDirty: Bool { editorTextView.string != lastSyncedContent }

    private func updateButtonsForSelection() {
        let canSave = selection == .system || canEditCurrentSelection
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

        updateFindBarState(scrollToCurrent: false)
    }

    // MARK: - Sidebar State

    private func applyStoredSidebarWidthIfNeeded(force: Bool = false) {
        guard let splitView, splitView.subviews.count > 1, splitView.bounds.width > 0 else { return }
        guard force || !didApplyInitialSidebarWidth else { return }

        let maxWidth = max(CGFloat(AppSettings.minSidebarWidth), splitView.bounds.width - 150)
        let width = min(CGFloat(settings.sidebarWidth), maxWidth)

        isApplyingStoredSidebarWidth = true
        splitView.setPosition(width, ofDividerAt: 0)
        isApplyingStoredSidebarWidth = false

        syncProfileColumnWidth()
        didApplyInitialSidebarWidth = true
    }

    private func syncProfileColumnWidth() {
        let availableWidth = max(120, sidebarScroll.contentSize.width - 2)
        sidebarColumn?.width = availableWidth
    }

    // MARK: - Find / Replace

    private func presentFindBar(showReplace: Bool, focusReplaceField: Bool) {
        findBarView.isHidden = false
        if showReplace && canEditCurrentSelection {
            isReplaceBarExpanded = true
        }
        seedFindQueryFromSelectionIfNeeded()
        refreshFindResults(scrollToCurrent: true)
        updateFindBarState(scrollToCurrent: false)

        let targetField: NSTextField = focusReplaceField && isReplaceBarExpanded && canEditCurrentSelection
            ? findBarView.replaceField
            : findBarView.findField
        view.window?.makeFirstResponder(targetField)
        targetField.selectText(nil)
    }

    private func seedFindQueryFromSelectionIfNeeded() {
        guard findBarView.findField.stringValue.isEmpty,
              let selectionRange = editorTextView.selectedNSRanges.first,
              selectionRange.length > 0 else { return }

        let selectedText = (editorTextView.string as NSString).substring(with: selectionRange)
        guard !selectedText.contains(where: { $0.isNewline }) else { return }
        findBarView.findField.stringValue = selectedText
    }

    @objc private func closeFindBar(_ sender: Any?) {
        findBarView.isHidden = true
        isReplaceBarExpanded = false
        findMatches = []
        currentFindMatchIndex = nil
        editorTextView.clearSearchHighlights()
        view.window?.makeFirstResponder(editorTextView)
    }

    @objc private func findNextMatch(_ sender: Any?) {
        navigateFindMatch(forward: true)
    }

    @objc private func findPreviousMatch(_ sender: Any?) {
        navigateFindMatch(forward: false)
    }

    @objc private func toggleReplacePanel(_ sender: Any?) {
        guard canEditCurrentSelection else { return }
        isReplaceBarExpanded.toggle()
        updateFindBarState(scrollToCurrent: false)
        if isReplaceBarExpanded {
            view.window?.makeFirstResponder(findBarView.replaceField)
            findBarView.replaceField.selectText(nil)
        }
    }

    @objc private func replaceCurrentMatch(_ sender: Any?) {
        guard canEditCurrentSelection, let currentFindRange else { return }

        let replacement = findBarView.replaceField.stringValue
        let result = HostsEditorTextEditing.replaceMatch(
            in: editorTextView.string,
            matchRange: currentFindRange,
            with: replacement
        )
        applyEditorMutation(result)
    }

    @objc private func replaceAllMatches(_ sender: Any?) {
        guard canEditCurrentSelection else { return }

        let result = HostsEditorTextEditing.replaceAllMatches(
            in: editorTextView.string,
            query: findBarView.findField.stringValue,
            with: findBarView.replaceField.stringValue
        )
        guard result.text != editorTextView.string else { return }
        applyEditorMutation(result)
    }

    private func navigateFindMatch(forward: Bool) {
        guard isFindBarVisible else {
            presentFindBar(showReplace: false, focusReplaceField: false)
            return
        }
        guard !findMatches.isEmpty else {
            NSSound.beep()
            return
        }

        if let currentFindMatchIndex {
            if forward {
                self.currentFindMatchIndex = (currentFindMatchIndex + 1) % findMatches.count
            } else {
                self.currentFindMatchIndex = (currentFindMatchIndex - 1 + findMatches.count) % findMatches.count
            }
        } else {
            currentFindMatchIndex = 0
        }

        updateFindBarState(scrollToCurrent: true)
    }

    private func refreshFindResults(scrollToCurrent: Bool) {
        guard isFindBarVisible else {
            editorTextView.clearSearchHighlights()
            return
        }

        let query = findBarView.findField.stringValue
        guard !query.isEmpty else {
            findMatches = []
            currentFindMatchIndex = nil
            updateFindBarState(scrollToCurrent: false)
            return
        }

        let previousRange = currentFindRange
        findMatches = HostsEditorTextEditing.matchRanges(in: editorTextView.string, query: query)

        if let previousRange, let sameIndex = findMatches.firstIndex(of: previousRange) {
            currentFindMatchIndex = sameIndex
        } else if let selectionRange = editorTextView.selectedNSRanges.first,
                  let selectedIndex = HostsEditorTextEditing.firstMatchIndex(containing: selectionRange, within: findMatches) {
            currentFindMatchIndex = selectedIndex
        } else {
            currentFindMatchIndex = findMatches.isEmpty ? nil : 0
        }

        updateFindBarState(scrollToCurrent: scrollToCurrent)
    }

    private func updateFindBarState(scrollToCurrent: Bool) {
        guard findBarView != nil else { return }

        let canReplace = canEditCurrentSelection
        if !canReplace {
            isReplaceBarExpanded = false
        }

        findBarView.setReplaceAvailable(canReplace)
        findBarView.setReplaceVisible(isReplaceBarExpanded && canReplace)

        let currentDisplayIndex = currentFindMatchIndex.flatMap { index in
            findMatches.indices.contains(index) ? index + 1 : nil
        }
        findBarView.updateMatchCount(current: currentDisplayIndex, total: findMatches.count)

        let hasMatches = !findMatches.isEmpty
        findBarView.previousButton.isEnabled = hasMatches
        findBarView.nextButton.isEnabled = hasMatches
        findBarView.replaceButton.isEnabled = canReplace && hasMatches
        findBarView.replaceAllButton.isEnabled = canReplace && hasMatches

        if isFindBarVisible {
            editorTextView.updateSearchHighlights(matches: findMatches, currentIndex: currentFindMatchIndex, scrollToCurrent: scrollToCurrent)
        } else {
            editorTextView.clearSearchHighlights()
        }
    }

    private func applyEditorMutation(_ result: HostsEditorTextEditResult) {
        guard editorTextView.applyEditedText(result.text, selectedRanges: result.selectedRanges) else { return }
        refreshFindResults(scrollToCurrent: true)
        updateButtonsForSelection()
    }

    // MARK: - Actions

    @objc private func editorTextDidChange(_ note: Notification) {
        refreshFindResults(scrollToCurrent: false)
        updateButtonsForSelection()
    }

    @objc private func showNewProfileMenu() {
        let menu = NSMenu()
        let localItem = NSMenuItem(title: L10n.mainLocalProfile, action: #selector(addLocalProfile), keyEquivalent: "")
        localItem.target = self
        let remoteItem = NSMenuItem(title: L10n.mainRemoteProfile, action: #selector(showAddRemotePopover), keyEquivalent: "")
        remoteItem.target = self
        menu.addItem(localItem)
        menu.addItem(remoteItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addProfileButton.bounds.height), in: addProfileButton)
    }

    @objc private func addLocalProfile() {
        let profile = HostsProfile(name: L10n.mainNewProfileName, content: "")
        manager.addProfile(profile)
        selection = .profile(profile.id)
    }

    @objc private func showAddRemotePopover() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 56))
        content.wantsLayer = true

        let label = NSTextField(labelWithString: L10n.mainRemoteURL)
        remoteURLLabel = label
        content.addSubview(label)

        remoteURLField = NSTextField()
        remoteURLField.placeholderString = L10n.mainRemoteURLPlaceholder
        content.addSubview(remoteURLField)

        addRemoteConfirmButton = NSButton(title: L10n.mainAddRemoteConfirm, target: self, action: #selector(addRemoteFromPopover))
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
            manager.setErrorMessage(L10n.mainRemoteURLEmpty)
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
        let name = manager.profile(for: id)?.name ?? L10n.mainLocalProfile
        let alert = NSAlert()
        alert.messageText = L10n.mainDeleteProfileTitle(name)
        alert.informativeText = L10n.mainDeleteProfileMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.mainDelete)
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            performRemoveProfile()
        }
    }

    @objc private func toggleProfileEnabledFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = manager.profile(for: id) else { return }
        Task { await manager.setProfileEnabled(id: id, enabled: !profile.isEnabled) }
    }

    @objc private func refreshRemoteFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.manager.refreshRemoteProfile(id: id)
            await MainActor.run {
                self.pendingEdits.removeValue(forKey: id)
                if case .profile(let currentId) = self.selection, currentId == id {
                    self.syncEditorFromSelection()
                }
            }
        }
    }

    @objc private func removeProfileFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let targetRow = row(for: .profile(id))
        guard targetRow >= 0 else { return }
        profileTableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        selection = .profile(id)
        removeProfile()
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
            manager.setErrorMessage(L10n.tr("main.remote_profile_required"))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.manager.refreshRemoteProfile(id: id)
            await MainActor.run {
                self.pendingEdits.removeValue(forKey: id)
                self.syncEditorFromSelection()
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
            return makeSectionHeaderCell(title: L10n.mainSectionLocal)
        }
        if row == remoteHeaderRow {
            return makeSectionHeaderCell(title: L10n.mainSectionRemote)
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
            cell?.configureReadOnly(title: L10n.mainSystem)
        } else if row == baseRow {
            cell?.configureReadOnly(title: L10n.mainDefault)
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

// MARK: - NSTextFieldDelegate

extension ViewController: NSTextFieldDelegate, NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === findBarView.findField {
            refreshFindResults(scrollToCurrent: true)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        guard field !== findBarView.findField, field !== findBarView.replaceField else { return }
        guard let cell = field.superview as? ProfileCellView,
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

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === findBarView.findField {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                navigateFindMatch(forward: !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                closeFindBar(nil)
                return true
            }
        }

        if control === findBarView.replaceField {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                replaceCurrentMatch(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                closeFindBar(nil)
                return true
            }
        }

        return false
    }
}

// MARK: - NSSplitViewDelegate

extension ViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? CGFloat(AppSettings.minSidebarWidth) : proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        return index == 0 ? max(CGFloat(AppSettings.minSidebarWidth), splitView.bounds.width - 150) : proposedMaximumPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        syncProfileColumnWidth()
        guard Self.shouldPersistSidebarWidth(
                hasAppliedInitialWidth: didApplyInitialSidebarWidth,
                isApplyingStoredWidth: isApplyingStoredSidebarWidth
              ),
              let sidebar = splitView.subviews.first else { return }
        settings.sidebarWidth = Double(sidebar.frame.width)
    }
}

extension ViewController: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(makeTextLarger(_:)),
             #selector(makeTextSmaller(_:)),
             #selector(showFindBar(_:)),
             #selector(showReplaceBar(_:)):
            return view.window?.contentViewController === self
        case #selector(toggleCommentSelection(_:)):
            return view.window?.contentViewController === self && canEditCurrentSelection
        default:
            return true
        }
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

        let toggleTitle = profile.isEnabled ? L10n.mainContextDisable : L10n.mainContextEnable
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleProfileEnabledFromContextMenu(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.representedObject = id
        menu.addItem(toggleItem)

        if profile.isRemote {
            let refreshItem = NSMenuItem(title: L10n.mainRefreshRemote, action: #selector(refreshRemoteFromContextMenu(_:)), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.representedObject = id
            menu.addItem(refreshItem)
        }

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: L10n.mainContextDelete, action: #selector(removeProfileFromContextMenu(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = id
        menu.addItem(deleteItem)

        return menu
    }
}

extension ViewController {
    static func isEditingTextInput(
        responder: NSResponder?,
        editorTextView: NSTextView?,
        editorContainerView: NSView?
    ) -> Bool {
        if responder is NSTextView {
            return true
        }

        guard let view = responder as? NSView else { return false }
        if let editorTextView, view === editorTextView {
            return true
        }

        return editorContainerView.map { view.isDescendant(of: $0) } ?? false
    }

    static func shouldPersistSidebarWidth(
        hasAppliedInitialWidth: Bool,
        isApplyingStoredWidth: Bool
    ) -> Bool {
        hasAppliedInitialWidth && !isApplyingStoredWidth
    }

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

    var debugApplyButtonTitle: String {
        applyButton.title
    }

    var debugAddProfileButtonTitle: String {
        addProfileButton.title
    }

    var debugSidebarTitle: String {
        sidebarColumn.title
    }

    var debugFindPlaceholder: String {
        findBarView.findField.placeholderString ?? ""
    }

    var debugReplacePlaceholder: String {
        findBarView.replaceField.placeholderString ?? ""
    }

    var debugEditorString: String {
        editorTextView?.string ?? ""
    }

    var debugDidTriggerFullRehighlight: Bool {
        editorTextView?.didTriggerFullRehighlight ?? false
    }

    func selectProfileForTesting(id: String) {
        guard isViewLoaded else { return }
        let targetSelection = SidebarSelection.profile(id)
        let targetRow = row(for: targetSelection)
        profileTableView?.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        selection = targetSelection
        updateButtonsForSelection()
    }

    func handleProfilesDidChangeForTesting() {
        guard isViewLoaded else { return }
        reloadTablePreservingSelection()
        refreshEditorForCurrentSelectionAfterProfilesChange()
    }
}
