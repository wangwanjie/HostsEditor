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
    let previousButton = EditorFindBarView.makeSymbolButton(systemName: "chevron.up", description: "上一个结果")
    let nextButton = EditorFindBarView.makeSymbolButton(systemName: "chevron.down", description: "下一个结果")
    let replaceToggleButton = NSButton(title: "替换", target: nil, action: nil)
    let replaceButton = NSButton(title: "替换", target: nil, action: nil)
    let replaceAllButton = NSButton(title: "全部替换", target: nil, action: nil)
    let closeButton = EditorFindBarView.makeSymbolButton(systemName: "xmark", description: "关闭查找")

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
}

private extension EditorFindBarView {
    func buildUI() {
        findField.placeholderString = "查找"
        findField.focusRingType = .none

        replaceField.placeholderString = "替换"
        replaceField.focusRingType = .none

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

    static func makeSymbolButton(systemName: String, description: String) -> NSButton {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: description)
        image?.isTemplate = true

        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(description)
        return button
    }
}
