//
//  HostsEditorTextView.swift
//  HostsEditor
//

import AppKit

final class HostsEditorTextView: NSTextView {
    private let highlighter = HostsSyntaxHighlighter()
    private var didAttachHighlighter = false
    private(set) var didTriggerFullRehighlight = false

    var selectedNSRanges: [NSRange] {
        selectedRanges.map(\.rangeValue)
    }

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
        rehighlightEntireDocument()
    }

    func rehighlightEntireDocument() {
        attachHighlighterIfNeeded()
        didTriggerFullRehighlight = true
        highlighter.rehighlightEntireDocument()
    }

    @discardableResult
    func applyEditedText(_ newText: String, selectedRanges newSelectedRanges: [NSRange]? = nil) -> Bool {
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: fullRange, replacementString: newText) else { return false }

        textStorage?.replaceCharacters(in: fullRange, with: newText)
        didChangeText()

        if let newSelectedRanges {
            selectedRanges = newSelectedRanges.map(NSValue.init(range:))
        }
        return true
    }

    func updateSearchHighlights(matches: [NSRange], currentIndex: Int?, scrollToCurrent: Bool) {
        clearSearchHighlights()
        guard let layoutManager, let textContainer else { return }

        let colors = searchHighlightColors()
        for (index, range) in matches.enumerated() {
            guard range.location != NSNotFound else { continue }
            let color = currentIndex == index ? colors.current : colors.all
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }

        guard let currentIndex,
              matches.indices.contains(currentIndex) else { return }

        let currentRange = matches[currentIndex]
        guard scrollToCurrent else { return }

        _ = layoutManager.glyphRange(forCharacterRange: currentRange, actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        selectedRanges = [NSValue(range: currentRange)]
        scrollRangeToVisible(currentRange)
    }

    func clearSearchHighlights() {
        guard let layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }
}

private extension HostsEditorTextView {
    func searchHighlightColors() -> (all: NSColor, current: NSColor) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return (
                all: NSColor(calibratedRed: 0.58, green: 0.47, blue: 0.13, alpha: 0.55),
                current: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.18, alpha: 0.85)
            )
        }
        return (
            all: NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.54, alpha: 0.7),
            current: NSColor(calibratedRed: 0.99, green: 0.77, blue: 0.29, alpha: 0.95)
        )
    }
}
