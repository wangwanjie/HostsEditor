//
//  HostsEditorTextEditing.swift
//  HostsEditor
//

import Foundation

struct HostsEditorTextEditResult: Equatable {
    let text: String
    let selectedRanges: [NSRange]
}

enum HostsEditorTextEditing {
    nonisolated static func toggleComments(in text: String, selectedRanges: [NSRange]) -> HostsEditorTextEditResult {
        let source = text as NSString
        let lineRanges = mergedLineRanges(in: source, selectedRanges: selectedRanges)
        guard !lineRanges.isEmpty else {
            return HostsEditorTextEditResult(text: text, selectedRanges: selectedRanges)
        }

        let shouldUncomment = nonEmptyLines(in: source, lineRanges: lineRanges).allSatisfy(isCommentedLine(_:))
        let mutable = NSMutableString(string: text)
        var transformedSelections: [NSRange] = []

        for lineRange in lineRanges.reversed() {
            let originalBlock = mutable.substring(with: lineRange)
            let transformedBlock = transformBlock(originalBlock, shouldUncomment: shouldUncomment)
            mutable.replaceCharacters(in: lineRange, with: transformedBlock)
            transformedSelections.insert(
                NSRange(location: lineRange.location, length: (transformedBlock as NSString).length),
                at: 0
            )
        }

        return HostsEditorTextEditResult(text: mutable as String, selectedRanges: transformedSelections)
    }

    nonisolated static func matchRanges(in text: String, query: String, isCaseSensitive: Bool = false) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let string = text as NSString
        let options: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchRange = NSRange(location: 0, length: string.length)

        while searchRange.length > 0 {
            let match = string.range(of: query, options: options, range: searchRange)
            guard match.location != NSNotFound else { break }
            matches.append(match)

            let nextLocation = match.location + max(match.length, 1)
            guard nextLocation <= string.length else { break }
            searchRange = NSRange(location: nextLocation, length: string.length - nextLocation)
        }

        return matches
    }

    nonisolated static func firstMatchIndex(containing selectionRange: NSRange, within matches: [NSRange]) -> Int? {
        matches.firstIndex { match in
            NSIntersectionRange(match, selectionRange).length > 0 || match.location == selectionRange.location
        }
    }

    nonisolated static func replaceMatch(in text: String, matchRange: NSRange, with replacement: String) -> HostsEditorTextEditResult {
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: matchRange, with: replacement)
        return HostsEditorTextEditResult(
            text: mutable as String,
            selectedRanges: [NSRange(location: matchRange.location, length: (replacement as NSString).length)]
        )
    }

    nonisolated static func replaceAllMatches(in text: String, query: String, with replacement: String, isCaseSensitive: Bool = false) -> HostsEditorTextEditResult {
        let matches = matchRanges(in: text, query: query, isCaseSensitive: isCaseSensitive)
        guard !matches.isEmpty else {
            return HostsEditorTextEditResult(text: text, selectedRanges: [])
        }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match, with: replacement)
        }

        let cursorLocation = matches[0].location + (replacement as NSString).length
        return HostsEditorTextEditResult(
            text: mutable as String,
            selectedRanges: [NSRange(location: cursorLocation, length: 0)]
        )
    }
}

private extension HostsEditorTextEditing {
    nonisolated static func mergedLineRanges(in text: NSString, selectedRanges: [NSRange]) -> [NSRange] {
        let normalized = selectedRanges.compactMap { normalizedLineRange(in: text, selection: $0) }
            .sorted { lhs, rhs in
                if lhs.location == rhs.location { return lhs.length < rhs.length }
                return lhs.location < rhs.location
            }

        guard var current = normalized.first else { return [] }
        var merged: [NSRange] = []

        for range in normalized.dropFirst() {
            let currentEnd = current.location + current.length
            if range.location <= currentEnd {
                let nextEnd = max(currentEnd, range.location + range.length)
                current.length = nextEnd - current.location
            } else {
                merged.append(current)
                current = range
            }
        }

        merged.append(current)
        return merged
    }

    nonisolated static func normalizedLineRange(in text: NSString, selection: NSRange) -> NSRange? {
        guard text.length > 0 else { return nil }

        let startLocation = min(max(selection.location, 0), max(text.length - 1, 0))
        let startLine = text.lineRange(for: NSRange(location: startLocation, length: 0))

        if selection.length == 0 {
            return startLine
        }

        let endExclusive = min(selection.location + selection.length, text.length)
        let endLocation = max(startLocation, max(endExclusive - 1, 0))
        let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
        return NSUnionRange(startLine, endLine)
    }

    nonisolated static func nonEmptyLines(in text: NSString, lineRanges: [NSRange]) -> [String] {
        lineRanges.flatMap { lineRange -> [String] in
            let block = text.substring(with: lineRange)
            return splitIntoLineSegments(block)
                .map(\.content)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    nonisolated static func isCommentedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("#")
    }

    nonisolated static func transformBlock(_ block: String, shouldUncomment: Bool) -> String {
        splitIntoLineSegments(block)
            .map { transformLineSegment($0, shouldUncomment: shouldUncomment) }
            .joined()
    }

    nonisolated static func transformLineSegment(_ segment: LineSegment, shouldUncomment: Bool) -> String {
        let trimmed = segment.content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return segment.content + segment.lineBreak
        }

        let transformedContent: String
        if shouldUncomment {
            transformedContent = uncommentedLine(segment.content)
        } else {
            transformedContent = "# " + segment.content
        }

        return transformedContent + segment.lineBreak
    }

    nonisolated static func uncommentedLine(_ line: String) -> String {
        let whitespaceTrimmed = line.drop(while: { $0.isWhitespace })
        guard let hashIndex = whitespaceTrimmed.firstIndex(of: "#") else {
            return line
        }

        let contentStart = whitespaceTrimmed.index(after: hashIndex)
        let remainder = whitespaceTrimmed[contentStart...]
        return String(remainder.drop(while: { $0.isWhitespace }))
    }

    nonisolated static func splitIntoLineSegments(_ block: String) -> [LineSegment] {
        guard !block.isEmpty else { return [] }

        var segments: [LineSegment] = []
        var cursor = block.startIndex

        while cursor < block.endIndex {
            var lineEnd = cursor
            while lineEnd < block.endIndex, !block[lineEnd].isNewline {
                lineEnd = block.index(after: lineEnd)
            }

            var newlineEnd = lineEnd
            while newlineEnd < block.endIndex, block[newlineEnd].isNewline {
                newlineEnd = block.index(after: newlineEnd)
            }

            segments.append(
                LineSegment(
                    content: String(block[cursor..<lineEnd]),
                    lineBreak: String(block[lineEnd..<newlineEnd])
                )
            )
            cursor = newlineEnd
        }

        return segments
    }
}

private struct LineSegment {
    let content: String
    let lineBreak: String
}
