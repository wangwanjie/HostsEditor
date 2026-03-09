//
//  HostsSyntaxHighlighter.swift
//  HostsEditor
//
//  Hosts 文件语法高亮：注释、IP、主机名。
//

import AppKit

struct HostsHighlightTheme {
    var comment: NSColor
    var ipAddress: NSColor
    var hostname: NSColor
    var defaultText: NSColor

    static func forAppearance(_ appearance: NSAppearance?) -> HostsHighlightTheme {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return HostsHighlightTheme(
                comment: NSColor(calibratedWhite: 0.5, alpha: 1),
                ipAddress: NSColor(red: 0.4, green: 0.7, blue: 1, alpha: 1),
                hostname: NSColor(red: 0.7, green: 0.9, blue: 0.6, alpha: 1),
                defaultText: NSColor.textColor
            )
        } else {
            return HostsHighlightTheme(
                comment: NSColor(calibratedWhite: 0.4, alpha: 1),
                ipAddress: NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1),
                hostname: NSColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1),
                defaultText: NSColor.textColor
            )
        }
    }
}

final class HostsSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    private weak var textStorage: NSTextStorage?
    private var theme: HostsHighlightTheme { HostsHighlightTheme.forAppearance(NSApp.effectiveAppearance) }

    func attach(to textStorage: NSTextStorage) {
        self.textStorage = textStorage
        textStorage.delegate = self
        applyHighlight(to: NSRange(location: 0, length: textStorage.length))
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let extended = NSRange(location: max(0, editedRange.location - 512), length: min(textStorage.length, editedRange.length + 1024))
        applyHighlight(to: extended)
    }

    private func applyHighlight(to range: NSRange) {
        guard let storage = textStorage, range.length > 0, range.location < storage.length else { return }
        let string = storage.string as NSString
        let safeRange = NSRange(location: range.location, length: min(range.length, string.length - range.location))
        guard safeRange.location >= 0 else { return }

        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: safeRange)
        storage.addAttribute(.foregroundColor, value: theme.defaultText, range: safeRange)

        // 注释：# 到行尾
        let commentPattern = try? NSRegularExpression(pattern: "#[^\n]*", options: [])
        commentPattern?.enumerateMatches(in: string as String, options: [], range: safeRange) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: theme.comment, range: r)
        }

        // IPv4
        let ipPattern = try? NSRegularExpression(pattern: "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b", options: [])
        ipPattern?.enumerateMatches(in: string as String, options: [], range: safeRange) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: theme.ipAddress, range: r)
        }

        // 主机名：IP 后的第一个“词”（同一行）
        let lineRange = string.lineRange(for: safeRange)
        let lineContent = string.substring(with: lineRange)
        let lineStart = lineRange.location
        let hostnamePattern = try? NSRegularExpression(pattern: "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\s+([^\\s#\n]+)", options: [])
        let lineNS = lineContent as NSString
        hostnamePattern?.enumerateMatches(in: lineContent, options: [], range: NSRange(location: 0, length: lineNS.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges > 1 else { return }
            let nsHost = match.range(at: 1)
            let globalRange = NSRange(location: lineStart + nsHost.location, length: nsHost.length)
            if storage.length >= globalRange.location + globalRange.length {
                storage.addAttribute(.foregroundColor, value: theme.hostname, range: globalRange)
            }
        }

        storage.endEditing()
    }
}
