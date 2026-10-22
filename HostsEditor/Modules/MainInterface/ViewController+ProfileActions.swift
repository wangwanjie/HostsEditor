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
        // 先在本地校验地址格式，避免无效地址也关闭输入框
        do {
            _ = try HostsManager.validatedRemoteURL(from: url)
        } catch {
            manager.setErrorMessage(error.localizedDescription)
            return
        }
        addRemotePopover?.close()
        addRemotePopover = nil
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            // 直接使用返回的方案 id 定位，避免同一 URL 存在多个方案时选错
            guard let profileId = await manager.addRemoteProfile(urlString: url) else {
                return
            }
            selectProfile(id: profileId)
        }
    }

    /// 选中指定方案并同步编辑器
    func selectProfile(id: String) {
        let targetRow = row(for: .profile(id))
        profileTableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        selection = .profile(id)
    }

    @objc func newLocalProfileFromMenu(_ sender: Any?) {
        addLocalProfile()
    }

    @objc func newRemoteProfileFromMenu(_ sender: Any?) {
        showAddRemotePopover()
    }

    @objc func saveAndApplyFromMenu(_ sender: Any?) {
        guard applyButton.isEnabled else {
            NSSound.beep()
            return
        }
        saveAndApply()
    }

    /// 从本地文件导入为新的本地方案
    @objc func importProfileFromFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = L10n.tr("main.import.message")
        panel.prompt = L10n.tr("main.import.prompt")

        guard let window = view.window else {
            return
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else {
                return
            }
            var lastImportedId: String?
            for url in panel.urls {
                do {
                    lastImportedId = try self.manager.importProfile(fromFileURL: url).id
                } catch {
                    self.manager.setErrorMessage(L10n.tr("main.import.failed", url.lastPathComponent, error.localizedDescription))
                }
            }
            if let lastImportedId {
                self.selectProfile(id: lastImportedId)
            }
        }
    }

    /// 将编辑器当前内容导出为文本文件
    @objc func exportCurrentContent(_ sender: Any?) {
        guard let window = view.window else {
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedExportFileName()
        panel.canCreateDirectories = true
        let content = editorTextView.string
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try Data(content.utf8).write(to: url, options: .atomic)
            } catch {
                self?.manager.setErrorMessage(L10n.tr("main.export.failed", error.localizedDescription))
            }
        }
    }

    func suggestedExportFileName() -> String {
        let baseName: String
        switch selection {
        case .system:
            baseName = "hosts"
        case .base:
            baseName = "hosts-base"
        case .profile(let id):
            baseName = manager.profile(for: id)?.name ?? "hosts"
        }
        // 文件名中去掉路径分隔符，避免保存面板误判为子目录
        let sanitized = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return sanitized.isEmpty ? "hosts.txt" : "\(sanitized).txt"
    }

    /// 在 Finder 中打开 hosts 备份目录
    @objc func showBackupsInFinder(_ sender: Any?) {
        guard let directory = manager.backupDirectoryURL else {
            NSSound.beep()
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    @objc func duplicateProfileFromContextMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let copy = manager.duplicateProfile(id: id) else {
            return
        }
        selectProfile(id: copy.id)
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
        guard let id = sender.representedObject as? String else {
            return
        }
        refreshRemoteProfile(id: id)
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
        refreshRemoteProfile(id: id)
    }

    /// 刷新远程方案，完成后若仍选中该方案则同步编辑器内容
    func refreshRemoteProfile(id: String) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await manager.refreshRemoteProfile(id: id)
            pendingEdits.removeValue(forKey: id)
            if case .profile(let currentId) = selection, currentId == id {
                syncEditorFromSelection()
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
