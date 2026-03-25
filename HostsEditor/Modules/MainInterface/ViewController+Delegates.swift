import Cocoa
import SnapKit

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
            let index = row - 3
            cell?.configure(with: localProfiles[index])
        } else if row >= remoteProfileRow(0), row < remoteProfileRow(remoteProfiles.count) {
            let index = row - (3 + localProfiles.count + 1)
            cell?.configure(with: remoteProfiles[index])
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        isSelectableRow(row)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingTable else { return }
        if case .profile(let previousId) = selection {
            pendingEdits[previousId] = editorTextView.string
        }
        let row = profileTableView.selectedRow
        if let nextSelection = selection(forRow: row) {
            selection = nextSelection
        }
        updateButtonsForSelection()
    }
}

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

extension ViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        index == 0 ? CGFloat(AppSettings.minSidebarWidth) : proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        index == 0 ? max(CGFloat(AppSettings.minSidebarWidth), splitView.bounds.width - 150) : proposedMaximumPosition
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
