//
//  EditorFindBarView.swift
//  HostsEditor
//

import AppKit
import SnapKit

final class EditorFindBarView: NSVisualEffectView {
    let findField = NSSearchField()
    let replaceField = NSTextField()
    let matchCountLabel = NSTextField(labelWithString: "")
    let previousButton = EditorFindBarView.makeSymbolButton(systemName: "chevron.up")
    let nextButton = EditorFindBarView.makeSymbolButton(systemName: "chevron.down")
    let replaceToggleButton = NSButton(title: "", target: nil, action: nil)
    let replaceButton = NSButton(title: "", target: nil, action: nil)
    let replaceAllButton = NSButton(title: "", target: nil, action: nil)
    let closeButton = EditorFindBarView.makeSymbolButton(systemName: "xmark")

    private let findRow = NSView()
    private let replaceRow = NSView()
    private var replaceRowHeightConstraint: Constraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        buildUI()
        applyLocalization()
        setReplaceVisible(false)
        updateMatchCount(current: nil, total: 0)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func setReplaceVisible(_ isVisible: Bool) {
        replaceRow.isHidden = !isVisible
        replaceRowHeightConstraint?.update(offset: isVisible ? 30 : 0)
        invalidateIntrinsicContentSize()
    }

    func setReplaceAvailable(_ isAvailable: Bool) {
        replaceToggleButton.isHidden = !isAvailable
        if !isAvailable {
            setReplaceVisible(false)
        }
    }

    func updateMatchCount(current: Int?, total: Int) {
        guard total > 0, let current else {
            matchCountLabel.stringValue = total == 0 ? "0" : "\(total)"
            return
        }
        matchCountLabel.stringValue = "\(current)/\(total)"
    }

    func applyLocalization() {
        findField.placeholderString = L10n.findPlaceholder
        replaceField.placeholderString = L10n.replacePlaceholder
        replaceToggleButton.title = L10n.replaceButton
        replaceButton.title = L10n.replaceButton
        replaceAllButton.title = L10n.replaceAllButton
        previousButton.toolTip = L10n.accessibilityPreviousResult
        previousButton.setAccessibilityLabel(L10n.accessibilityPreviousResult)
        nextButton.toolTip = L10n.accessibilityNextResult
        nextButton.setAccessibilityLabel(L10n.accessibilityNextResult)
        closeButton.toolTip = L10n.accessibilityCloseFind
        closeButton.setAccessibilityLabel(L10n.accessibilityCloseFind)
    }
}

private extension EditorFindBarView {
    func buildUI() {
        findField.focusRingType = .none
        findField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        replaceField.focusRingType = .none
        replaceField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        matchCountLabel.alignment = .center
        matchCountLabel.textColor = .secondaryLabelColor
        matchCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        replaceToggleButton.bezelStyle = .texturedRounded
        replaceButton.bezelStyle = .rounded
        replaceAllButton.bezelStyle = .rounded

        addSubview(findRow)
        addSubview(replaceRow)

        findRow.addSubview(findField)
        findRow.addSubview(matchCountLabel)
        findRow.addSubview(previousButton)
        findRow.addSubview(nextButton)
        findRow.addSubview(replaceToggleButton)
        findRow.addSubview(closeButton)

        replaceRow.addSubview(replaceField)
        replaceRow.addSubview(replaceButton)
        replaceRow.addSubview(replaceAllButton)

        findRow.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(10)
            make.height.equalTo(30)
        }

        replaceRow.snp.makeConstraints { make in
            make.top.equalTo(findRow.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(10)
            replaceRowHeightConstraint = make.height.equalTo(0).constraint
        }

        findField.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }

        matchCountLabel.snp.makeConstraints { make in
            make.leading.equalTo(findField.snp.trailing).offset(8)
            make.width.greaterThanOrEqualTo(28)
            make.centerY.equalToSuperview()
        }

        previousButton.snp.makeConstraints { make in
            make.leading.equalTo(matchCountLabel.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(24)
        }

        nextButton.snp.makeConstraints { make in
            make.leading.equalTo(previousButton.snp.trailing).offset(4)
            make.centerY.width.height.equalTo(previousButton)
        }

        replaceToggleButton.snp.makeConstraints { make in
            make.leading.equalTo(nextButton.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
        }

        closeButton.snp.makeConstraints { make in
            make.leading.equalTo(replaceToggleButton.snp.trailing).offset(6)
            make.trailing.equalToSuperview()
            make.centerY.width.height.equalTo(previousButton)
        }

        replaceField.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }

        replaceButton.snp.makeConstraints { make in
            make.leading.equalTo(replaceField.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
        }

        replaceAllButton.snp.makeConstraints { make in
            make.leading.equalTo(replaceButton.snp.trailing).offset(8)
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }

    static func makeSymbolButton(systemName: String) -> NSButton {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.isTemplate = true

        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        return button
    }
}
