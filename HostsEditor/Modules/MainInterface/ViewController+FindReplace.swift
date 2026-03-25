import Cocoa

extension ViewController {
    func presentFindBar(showReplace: Bool, focusReplaceField: Bool) {
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

    func seedFindQueryFromSelectionIfNeeded() {
        guard findBarView.findField.stringValue.isEmpty,
              let selectionRange = editorTextView.selectedNSRanges.first,
              selectionRange.length > 0 else { return }

        let selectedText = (editorTextView.string as NSString).substring(with: selectionRange)
        guard !selectedText.contains(where: { $0.isNewline }) else { return }
        findBarView.findField.stringValue = selectedText
    }

    @objc func closeFindBar(_ sender: Any?) {
        findBarView.isHidden = true
        isReplaceBarExpanded = false
        findMatches = []
        currentFindMatchIndex = nil
        editorTextView.clearSearchHighlights()
        view.window?.makeFirstResponder(editorTextView)
    }

    @objc func findNextMatch(_ sender: Any?) {
        navigateFindMatch(forward: true)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        navigateFindMatch(forward: false)
    }

    @objc func toggleReplacePanel(_ sender: Any?) {
        guard canEditCurrentSelection else { return }
        isReplaceBarExpanded.toggle()
        updateFindBarState(scrollToCurrent: false)
        if isReplaceBarExpanded {
            view.window?.makeFirstResponder(findBarView.replaceField)
            findBarView.replaceField.selectText(nil)
        }
    }

    @objc func replaceCurrentMatch(_ sender: Any?) {
        guard canEditCurrentSelection, let currentFindRange else { return }

        let replacement = findBarView.replaceField.stringValue
        let result = HostsEditorTextEditing.replaceMatch(
            in: editorTextView.string,
            matchRange: currentFindRange,
            with: replacement
        )
        applyEditorMutation(result)
    }

    @objc func replaceAllMatches(_ sender: Any?) {
        guard canEditCurrentSelection else { return }

        let result = HostsEditorTextEditing.replaceAllMatches(
            in: editorTextView.string,
            query: findBarView.findField.stringValue,
            with: findBarView.replaceField.stringValue
        )
        guard result.text != editorTextView.string else { return }
        applyEditorMutation(result)
    }

    func navigateFindMatch(forward: Bool) {
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

    func refreshFindResults(scrollToCurrent: Bool) {
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

    func updateFindBarState(scrollToCurrent: Bool) {
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
            editorTextView.updateSearchHighlights(
                matches: findMatches,
                currentIndex: currentFindMatchIndex,
                scrollToCurrent: scrollToCurrent
            )
        } else {
            editorTextView.clearSearchHighlights()
        }
    }

    func applyEditorMutation(_ result: HostsEditorTextEditResult) {
        guard editorTextView.applyEditedText(result.text, selectedRanges: result.selectedRanges) else { return }
        refreshFindResults(scrollToCurrent: true)
        updateButtonsForSelection()
    }
}
