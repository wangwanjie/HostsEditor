import Cocoa

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
