//
//  ProfileRowView.swift
//  HostsEditor
//

import AppKit

final class ProfileRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let color = NSColor.selectedContentBackgroundColor
            color.setFill()
            dirtyRect.fill()
        }
    }
}
