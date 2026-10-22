import Foundation
import Testing
@testable import HostsEditor

struct HostsEditorTextEditingTests {
    @Test
    func toggleCommentsWithCaretCommentsOnlyCurrentLine() {
        let text = "1.1.1.1 a.test\n2.2.2.2 b.test"
        let caretOnSecondLine = NSRange(location: (text as NSString).range(of: "2.2.2.2").location + 2, length: 0)

        let result = HostsEditorTextEditing.toggleComments(in: text, selectedRanges: [caretOnSecondLine])

        #expect(result.text == "1.1.1.1 a.test\n# 2.2.2.2 b.test")
    }

    @Test
    func toggleCommentsCommentsAllWhenSelectionIsMixed() {
        let text = "# 1.1.1.1 a.test\n2.2.2.2 b.test"

        let result = HostsEditorTextEditing.toggleComments(
            in: text,
            selectedRanges: [NSRange(location: 0, length: (text as NSString).length)]
        )

        #expect(result.text == "# # 1.1.1.1 a.test\n# 2.2.2.2 b.test")
    }

    @Test
    func toggleCommentsKeepsBlankLinesAndCRLFLineBreaks() {
        let text = "1.1.1.1 a.test\r\n\r\n2.2.2.2 b.test\r\n"

        let result = HostsEditorTextEditing.toggleComments(
            in: text,
            selectedRanges: [NSRange(location: 0, length: (text as NSString).length)]
        )

        #expect(result.text == "# 1.1.1.1 a.test\r\n\r\n# 2.2.2.2 b.test\r\n")
    }

    @Test
    func toggleCommentsOnEmptyTextIsNoOp() {
        let result = HostsEditorTextEditing.toggleComments(in: "", selectedRanges: [NSRange(location: 0, length: 0)])

        #expect(result.text == "")
    }

    @Test
    func toggleCommentsTwiceRestoresOriginalText() {
        let text = "1.1.1.1 a.test\n2.2.2.2 b.test"
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        let commented = HostsEditorTextEditing.toggleComments(in: text, selectedRanges: [fullRange])
        let restored = HostsEditorTextEditing.toggleComments(in: commented.text, selectedRanges: commented.selectedRanges)

        #expect(restored.text == text)
    }

    @Test
    func matchRangesRespectsCaseSensitivity() {
        let text = "Foo foo FOO"

        #expect(HostsEditorTextEditing.matchRanges(in: text, query: "foo").count == 3)
        #expect(HostsEditorTextEditing.matchRanges(in: text, query: "foo", isCaseSensitive: true) == [NSRange(location: 4, length: 3)])
        #expect(HostsEditorTextEditing.matchRanges(in: text, query: "").isEmpty)
    }

    @Test
    func matchRangesDoNotOverlap() {
        #expect(HostsEditorTextEditing.matchRanges(in: "aaaa", query: "aa") == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    @Test
    func firstMatchIndexFindsMatchContainingSelection() {
        let matches = [NSRange(location: 0, length: 3), NSRange(location: 10, length: 3)]

        #expect(HostsEditorTextEditing.firstMatchIndex(containing: NSRange(location: 5, length: 0), within: matches) == nil)
        #expect(HostsEditorTextEditing.firstMatchIndex(containing: NSRange(location: 11, length: 0), within: matches) == 1)
        #expect(HostsEditorTextEditing.firstMatchIndex(containing: NSRange(location: 10, length: 0), within: matches) == 1)
        #expect(HostsEditorTextEditing.firstMatchIndex(containing: NSRange(location: 11, length: 1), within: matches) == 1)
    }

    @Test
    func replaceMatchSelectsReplacementText() {
        let result = HostsEditorTextEditing.replaceMatch(
            in: "127.0.0.1 old.test",
            matchRange: NSRange(location: 10, length: 3),
            with: "brand-new"
        )

        #expect(result.text == "127.0.0.1 brand-new.test")
        #expect(result.selectedRanges == [NSRange(location: 10, length: 9)])
    }

    @Test
    func replaceAllWithoutMatchesLeavesTextUntouched() {
        let result = HostsEditorTextEditing.replaceAllMatches(in: "abc", query: "zzz", with: "y")

        #expect(result.text == "abc")
        #expect(result.selectedRanges.isEmpty)
    }

    @Test
    func replaceAllIsCaseInsensitiveByDefault() {
        let result = HostsEditorTextEditing.replaceAllMatches(in: "Foo foo", query: "foo", with: "bar")

        #expect(result.text == "bar bar")
    }
}
