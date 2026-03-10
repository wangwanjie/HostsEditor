//
//  ProfileCellView.swift
//  HostsEditor
//

import Cocoa

final class ProfileCellView: NSTableCellView {

    let checkbox: NSButton
    let nameField: NSTextField

    /// 当前展示的方案 ID，用于 rename 回调时定位
    var profileId: String?

    override init(frame: NSRect) {
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        nameField = NSTextField(labelWithString: "")
        nameField.isEditable = true
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frame)
        addSubview(checkbox)
        addSubview(nameField)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 18),

            nameField.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with profile: HostsProfile) {
        profileId = profile.id
        checkbox.state = profile.isEnabled ? .on : .off
        var title = profile.name
        if profile.isRemote { title += " ☁" }
        nameField.stringValue = title
    }
}
