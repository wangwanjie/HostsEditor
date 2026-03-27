import AppKit
import Testing
@testable import HostsEditor

struct HostsSyntaxHighlighterTests {
    @MainActor
    @Test
    func ipv6AddressReceivesIPAddressHighlight() {
        let storage = highlightedStorage(for: "2001:db8::1 example.test")
        let theme = HostsHighlightTheme.forAppearance(NSApp?.effectiveAppearance)

        assertColor(
            in: storage,
            for: "2001:db8::1",
            equals: theme.ipAddress
        )
    }

    @MainActor
    @Test
    func hostnameFollowingIPv6AddressReceivesHostnameHighlight() {
        let storage = highlightedStorage(for: "2001:db8::1 example.test")
        let theme = HostsHighlightTheme.forAppearance(NSApp?.effectiveAppearance)

        assertColor(
            in: storage,
            for: "example.test",
            equals: theme.hostname
        )
    }

    @MainActor
    @Test
    func disabledIPv6EntryUsesDisabledEntryHighlight() {
        let storage = highlightedStorage(for: "# ::1 localhost")
        let theme = HostsHighlightTheme.forAppearance(NSApp?.effectiveAppearance)

        assertColor(
            in: storage,
            for: "localhost",
            equals: theme.disabledEntry
        )
    }

    @MainActor
    private func highlightedStorage(for string: String) -> NSTextStorage {
        let storage = NSTextStorage(string: string)
        let highlighter = HostsSyntaxHighlighter()
        highlighter.attach(to: storage)
        return storage
    }

    private func assertColor(in storage: NSTextStorage, for substring: String, equals expected: NSColor) {
        let nsString = storage.string as NSString
        let range = nsString.range(of: substring)
        #expect(range.location != NSNotFound)

        guard range.location != NSNotFound else { return }

        let actual = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        let actualRGB = actual?.usingColorSpace(.deviceRGB)
        let expectedRGB = expected.usingColorSpace(.deviceRGB)

        #expect(actualRGB?.redComponent == expectedRGB?.redComponent)
        #expect(actualRGB?.greenComponent == expectedRGB?.greenComponent)
        #expect(actualRGB?.blueComponent == expectedRGB?.blueComponent)
        #expect(actualRGB?.alphaComponent == expectedRGB?.alphaComponent)
    }
}
