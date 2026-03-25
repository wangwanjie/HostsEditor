import Cocoa
import SnapKit

extension ViewController {
    func buildUI() {
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

    func buildSidebar() -> NSView {
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

    func buildEditorSection() -> NSView {
        let right = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: max(view.bounds.width - CGFloat(settings.sidebarWidth), 320),
                height: max(view.bounds.height, 320)
            )
        )
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
}
