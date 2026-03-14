//
//  ProfileCellView.swift
//  HostsEditor
//

import Cocoa
import SnapKit

final class ProfileCellView: NSTableCellView {

    let checkbox: NSButton
    let nameField: NSTextField

    /// 当前展示的方案 ID，用于 rename 回调时定位
    var profileId: String?

    override init(frame: NSRect) {
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

        nameField = NSTextField(labelWithString: "")
        nameField.isEditable = true
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.lineBreakMode = .byTruncatingTail

        super.init(frame: frame)
        addSubview(checkbox)
        addSubview(nameField)

        checkbox.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(6)
            make.centerY.equalToSuperview()
            make.width.equalTo(18)
        }

        nameField.snp.makeConstraints { make in
            make.leading.equalTo(checkbox.snp.trailing).offset(6)
            make.trailing.equalToSuperview().inset(6)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with profile: HostsProfile) {
        profileId = profile.id
        checkbox.isHidden = false
        checkbox.state = profile.isEnabled ? .on : .off
        nameField.isEditable = true
        var title = profile.name
        if profile.isRemote, !profile.name.hasPrefix("☁️") { title += " ☁" }
        nameField.stringValue = title
    }

    /// 只读项（如「系统」「默认」）：仅显示标题，无复选框、不可编辑
    func configureReadOnly(title: String) {
        profileId = nil
        checkbox.isHidden = true
        nameField.isEditable = false
        nameField.stringValue = title
    }
}
