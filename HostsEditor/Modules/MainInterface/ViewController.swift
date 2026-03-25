//
//  ViewController.swift
//  HostsEditor
//
//  Created by VanJay on 2026/3/9.
//

import Cocoa
import Combine
 
final class ViewController: NSViewController {

    static let mainWindowFrameAutosaveName = NSWindow.FrameAutosaveName("HostsEditorMainWindowFrame")

    let manager: HostsManager
    let settings: AppSettings
    var cancellables = Set<AnyCancellable>()

    var splitView: NSSplitView!
    var sidebarScroll: NSScrollView!
    var sidebarColumn: NSTableColumn!
    var profileTableView: ProfileTableView!
    var editorScroll: NSScrollView!
    var editorTextView: HostsEditorTextView!
    var findBarView: EditorFindBarView!
    var addProfileButton: NSButton!
    var removeProfileButton: NSButton!
    var applyButton: NSButton!
    var refreshButton: NSButton!
    var refreshRemoteButton: NSButton!
    var errorLabel: NSTextField!
    var addRemotePopover: NSPopover?
    var remoteURLLabel: NSTextField?
    var remoteURLField: NSTextField!
    var addRemoteConfirmButton: NSButton!
    var keyMonitor: Any?
    var didApplyInitialSidebarWidth = false
    var isApplyingStoredSidebarWidth = false
    var didConfigureWindowFrameAutosave = false
    var isReplaceBarExpanded = false
    var findMatches: [NSRange] = []
    var currentFindMatchIndex: Int?

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
    enum SidebarSelection: Equatable {
        case system
        case base
        case profile(String)
    }

    var selection: SidebarSelection = .system {
        didSet { syncEditorFromSelection() }
    }

    var lastSyncedContent: String = ""
    var pendingEdits: [String: String] = [:]
    var isUpdatingTable = false

    var localProfiles: [HostsProfile] { manager.profiles.filter { !$0.isRemote } }
    var remoteProfiles: [HostsProfile] { manager.profiles.filter { $0.isRemote } }

    let localHeaderRow = 0
    let systemRow = 1
    let baseRow = 2
    func localProfileRow(_ index: Int) -> Int { 3 + index }
    var remoteHeaderRow: Int { 3 + localProfiles.count }
    func remoteProfileRow(_ index: Int) -> Int { 3 + localProfiles.count + 1 + index }
    var totalRows: Int { 4 + localProfiles.count + remoteProfiles.count }
    var isFindBarVisible: Bool { findBarView != nil && !findBarView.isHidden }
    var currentFindRange: NSRange? {
        guard let currentFindMatchIndex, findMatches.indices.contains(currentFindMatchIndex) else { return nil }
        return findMatches[currentFindMatchIndex]
    }
    var canEditCurrentSelection: Bool {
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
    func isSelectableRow(_ row: Int) -> Bool {
        row != localHeaderRow && row != remoteHeaderRow
    }

    func selection(forRow row: Int) -> SidebarSelection? {
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

    func row(for selection: SidebarSelection) -> Int {
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
}
