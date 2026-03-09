//
//  HostsEditorTextView.swift
//  HostsEditor
//

import AppKit

final class HostsEditorTextView: NSTextView {
    private let highlighter = HostsSyntaxHighlighter()
    private var didAttachHighlighter = false

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
