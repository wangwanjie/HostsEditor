//
//  HostsEditorTextView.swift
//  HostsEditor
//

import AppKit

final class HostsEditorTextView: NSTextView {
    private let highlighter = HostsSyntaxHighlighter()
    private var didAttachHighlighter = false

    func applyEditorFontSize(_ pointSize: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        self.font = font
        typingAttributes[.font] = font

        guard let storage = textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachHighlighterIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachHighlighterIfNeeded()
    }

    private func attachHighlighterIfNeeded() {
        guard !didAttachHighlighter, let storage = self.textStorage else { return }
        highlighter.attach(to: storage)
        didAttachHighlighter = true
    }

    /// 供外部在设置完内容后调用，确保语法高亮生效
    func setupSyntaxHighlighting() {
        didAttachHighlighter = false
        attachHighlighterIfNeeded()
    }
}
