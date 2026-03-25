import Cocoa
import Combine

extension ViewController {
    var isContentDirty: Bool { editorTextView.string != lastSyncedContent }

    func setupBindings() {
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

    func applyLocalization() {
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

    func reloadTablePreservingSelection() {
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

    func syncEditorFromSelection() {
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
            if let profile = manager.profile(for: id) {
                let content = pendingEdits[id] ?? profile.content
                editorTextView.string = content
                editorTextView.isEditable = !profile.isRemote
                lastSyncedContent = profile.content
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

    func refreshEditorForCurrentSelectionAfterProfilesChange() {
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

    func updateButtonsForSelection() {
        let canSave = selection == .system || canEditCurrentSelection
        applyButton.isEnabled = canSave && isContentDirty && !manager.isLoading

        let isDeletableProfile: Bool
        if case .profile = selection {
            isDeletableProfile = true
        } else {
            isDeletableProfile = false
        }
        removeProfileButton.isEnabled = isDeletableProfile && !manager.isLoading

        refreshButton.isHidden = selection != .system
        if case .profile(let id) = selection, manager.profile(for: id)?.isRemote == true {
            refreshRemoteButton.isHidden = false
        } else {
            refreshRemoteButton.isHidden = true
        }

        updateFindBarState(scrollToCurrent: false)
    }

    func applyStoredSidebarWidthIfNeeded(force: Bool = false) {
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

    func syncProfileColumnWidth() {
        let availableWidth = max(120, sidebarScroll.contentSize.width - 2)
        sidebarColumn?.width = availableWidth
    }
}
