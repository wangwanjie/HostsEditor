import Cocoa
import SnapKit

extension ViewController {
    @objc func editorTextDidChange(_ note: Notification) {
        refreshFindResults(scrollToCurrent: false)
        updateButtonsForSelection()
    }

    @objc func showNewProfileMenu() {
        let menu = NSMenu()
        let localItem = NSMenuItem(title: L10n.mainLocalProfile, action: #selector(addLocalProfile), keyEquivalent: "")
        localItem.target = self
        let remoteItem = NSMenuItem(title: L10n.mainRemoteProfile, action: #selector(showAddRemotePopover), keyEquivalent: "")
        remoteItem.target = self
        menu.addItem(localItem)
        menu.addItem(remoteItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addProfileButton.bounds.height), in: addProfileButton)
    }

    @objc func addLocalProfile() {
        let profile = HostsProfile(name: L10n.mainNewProfileName, content: "")
        manager.addProfile(profile)
        selection = .profile(profile.id)
    }

    @objc func showAddRemotePopover() {
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

    @objc func addRemoteFromPopover() {
        let url = remoteURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            manager.setErrorMessage(L10n.mainRemoteURLEmpty)
            return
        }
        addRemotePopover?.close()
        addRemotePopover = nil
        Task {
            await manager.addRemoteProfile(urlString: url)
            if let profile = manager.profiles.first(where: { $0.remoteURL == url }) {
                let row = row(for: .profile(profile.id))
                profileTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                selection = .profile(profile.id)
            }
        }
    }

    func performRemoveProfile() {
        guard case .profile(let id) = selection else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didDelete = await manager.deleteProfile(id: id)
            guard didDelete else { return }

            pendingEdits.removeValue(forKey: id)
            profileTableView.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
            selection = .system
        }
    }

    @objc func removeProfile() {
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

    @objc func toggleProfileEnabledFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = manager.profile(for: id) else { return }
        Task { await manager.setProfileEnabled(id: id, enabled: !profile.isEnabled) }
    }

    @objc func refreshRemoteFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Task { [weak self] in
            guard let self else { return }
            await manager.refreshRemoteProfile(id: id)
            await MainActor.run {
                self.pendingEdits.removeValue(forKey: id)
                if case .profile(let currentId) = self.selection, currentId == id {
                    self.syncEditorFromSelection()
                }
            }
        }
    }

    @objc func removeProfileFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let targetRow = row(for: .profile(id))
        guard targetRow >= 0 else { return }
        profileTableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        selection = .profile(id)
        removeProfile()
    }

    @objc func saveAndApply() {
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

    @objc func refreshCurrentHosts() {
        Task { [weak self] in
            guard let self else { return }
            await manager.refreshSystemContent()
            await MainActor.run {
                self.syncEditorFromSelection()
            }
        }
    }

    @objc func refreshRemote() {
        guard case .profile(let id) = selection, manager.profile(for: id)?.isRemote == true else {
            manager.setErrorMessage(L10n.tr("main.remote_profile_required"))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await manager.refreshRemoteProfile(id: id)
            await MainActor.run {
                self.pendingEdits.removeValue(forKey: id)
                self.syncEditorFromSelection()
            }
        }
    }

    @objc func toggleProfileEnabled(_ sender: NSButton) {
        let row = profileTableView.row(for: sender)
        guard let selection = selection(forRow: row), case .profile(let id) = selection else { return }
        let enabled = sender.state == .on
        Task { await manager.setProfileEnabled(id: id, enabled: enabled) }
    }
}
