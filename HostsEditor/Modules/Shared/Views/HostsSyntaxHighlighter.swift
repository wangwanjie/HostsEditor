//
//  HostsSyntaxHighlighter.swift
//  HostsEditor
//
//  Hosts 文件语法高亮：注释、IP、主机名。
//

import AppKit
import Darwin

struct HostsHighlightTheme {
    var comment: NSColor
    var disabledEntry: NSColor
    var ipAddress: NSColor
    var hostname: NSColor
    var defaultText: NSColor

    static func forAppearance(_ appearance: NSAppearance?) -> HostsHighlightTheme {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return HostsHighlightTheme(
                comment: NSColor(calibratedWhite: 0.5, alpha: 1),
                disabledEntry: NSColor(calibratedRed: 0.88, green: 0.63, blue: 0.52, alpha: 1),
                ipAddress: NSColor(red: 0.4, green: 0.7, blue: 1, alpha: 1),
                hostname: NSColor(red: 0.7, green: 0.9, blue: 0.6, alpha: 1),
                defaultText: NSColor.textColor
            )
        } else {
            return HostsHighlightTheme(
                comment: NSColor(calibratedWhite: 0.4, alpha: 1),
                disabledEntry: NSColor(calibratedRed: 0.67, green: 0.34, blue: 0.24, alpha: 1),
                ipAddress: NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1),
                hostname: NSColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1),
                defaultText: NSColor.textColor
            )
        }
    }
}

final class HostsSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    private static let entryPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:#\s*)?([^\s#]+)(?:\s+([^\s#]+))?"#,
        options: []
    )
    private static let disabledLinePattern = try! NSRegularExpression(pattern: #"^\s*#"#, options: [])

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

    func rehighlightEntireDocument() {
        guard let textStorage else { return }
        applyHighlight(to: NSRange(location: 0, length: textStorage.length))
    }

    private func applyHighlight(to range: NSRange) {
        guard let storage = textStorage, range.length > 0, range.location < storage.length else { return }
        let string = storage.string as NSString
        let safeRange = NSRange(location: range.location, length: min(range.length, string.length - range.location))
        guard safeRange.location >= 0 else { return }
        let highlightRange = string.lineRange(for: safeRange)

        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: highlightRange)
        storage.addAttribute(.foregroundColor, value: theme.defaultText, range: highlightRange)

        enumerateLineContentRanges(in: string, within: highlightRange) { lineRange in
            applyHighlightingForLine(in: storage, string: string, lineRange: lineRange)
        }

        storage.endEditing()
    }

    private func applyHighlightingForLine(in storage: NSTextStorage, string: NSString, lineRange: NSRange) {
        let lineContent = string.substring(with: lineRange)
        let lineNSString = lineContent as NSString
        let lineSearchRange = NSRange(location: 0, length: lineNSString.length)

        let commentRange = lineNSString.range(of: "#")
        if commentRange.location != NSNotFound {
            let globalCommentRange = NSRange(location: lineRange.location + commentRange.location, length: commentRange.length)
            storage.addAttribute(.foregroundColor, value: theme.comment, range: globalCommentRange)
        }

        guard let match = Self.entryPattern.firstMatch(in: lineContent, options: [], range: lineSearchRange) else { return }

        let ipTokenRange = match.range(at: 1)
        guard ipTokenRange.location != NSNotFound else { return }

        let ipToken = lineNSString.substring(with: ipTokenRange)
        guard Self.isIPAddress(ipToken) else { return }

        let globalIPRange = NSRange(location: lineRange.location + ipTokenRange.location, length: ipTokenRange.length)
        storage.addAttribute(.foregroundColor, value: theme.ipAddress, range: globalIPRange)

        let hostnameRange = match.range(at: 2)
        if hostnameRange.location != NSNotFound {
            let globalHostnameRange = NSRange(location: lineRange.location + hostnameRange.location, length: hostnameRange.length)
            storage.addAttribute(.foregroundColor, value: theme.hostname, range: globalHostnameRange)
        }

        let isDisabledLine = Self.disabledLinePattern.firstMatch(in: lineContent, options: [], range: lineSearchRange) != nil
        if isDisabledLine {
            storage.addAttribute(.foregroundColor, value: theme.disabledEntry, range: lineRange)
        }
    }

    private func enumerateLineContentRanges(in string: NSString, within range: NSRange, using block: (NSRange) -> Void) {
        var currentLocation = range.location
        let endLocation = range.location + range.length

        while currentLocation < endLocation {
            let fullLineRange = string.lineRange(for: NSRange(location: currentLocation, length: 0))
            let contentRange = contentRange(forFullLineRange: fullLineRange, in: string)
            if contentRange.length > 0 {
                block(contentRange)
            }

            let nextLocation = fullLineRange.location + fullLineRange.length
            if nextLocation <= currentLocation {
                break
            }
            currentLocation = nextLocation
        }
    }

    private func contentRange(forFullLineRange fullLineRange: NSRange, in string: NSString) -> NSRange {
        var contentRange = fullLineRange
        while contentRange.length > 0 {
            let lastCharacter = string.character(at: contentRange.location + contentRange.length - 1)
            if lastCharacter == 10 || lastCharacter == 13 {
                contentRange.length -= 1
            } else {
                break
            }
        }
        return contentRange
    }

    private static func isIPAddress(_ token: String) -> Bool {
        var ipv4Address = in_addr()
        if token.withCString({ inet_pton(AF_INET, $0, &ipv4Address) == 1 }) {
            return true
        }

        var ipv6Address = in6_addr()
        return token.withCString { inet_pton(AF_INET6, $0, &ipv6Address) == 1 }
    }
}
