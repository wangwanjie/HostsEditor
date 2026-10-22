import Foundation
import Testing
@testable import HostsEditor

@MainActor
struct HostsComposeTests {
    private let base = "127.0.0.1 localhost\n::1 localhost"

    @Test
    func composeAppendsEnabledProfilesAsMarkedBlocksWithTrailingNewline() {
        let enabled = HostsProfile(id: "p1", name: "Dev", content: "10.0.0.1 dev.test", isEnabled: true)
        let disabled = HostsProfile(id: "p2", name: "Off", content: "10.0.0.2 off.test", isEnabled: false)

        let composed = HostsManager.composeHostsContent(base: base, profiles: [enabled, disabled])

        #expect(composed.hasPrefix(base + "\n\n# HostsEditor:BEGIN:p1"))
        #expect(composed.contains("10.0.0.1 dev.test"))
        #expect(!composed.contains("off.test"))
        #expect(composed.hasSuffix("# HostsEditor:END:p1\n"))
    }

    @Test
    func composeSkipsEnabledProfilesWithBlankContent() {
        let blank = HostsProfile(id: "blank", name: "Blank", content: "  \n\n", isEnabled: true)

        #expect(HostsManager.composeHostsContent(base: base, profiles: [blank]) == base + "\n")
        #expect(HostsManager.composeHostsContent(base: "", profiles: [blank]) == "")
    }

    @Test
    func extractBaseContentIsInverseOfCompose() {
        let profiles = [
            HostsProfile(id: "a", name: "A", content: "1.1.1.1 a.test", isEnabled: true),
            HostsProfile(id: "b", name: "B", content: "2.2.2.2 b.test\n# comment", isEnabled: true),
        ]

        let composed = HostsManager.composeHostsContent(base: base, profiles: profiles)

        #expect(HostsManager.extractBaseContent(from: composed) == base)
    }

    @Test
    func extractBaseContentKeepsUnmatchedMarkersInsteadOfSwallowingUserContent() {
        // BEGIN 与 END 的 id 不一致时不应把两者之间的用户内容当成托管块删掉
        let content = """
        127.0.0.1 localhost
        # HostsEditor:BEGIN:one
        10.0.0.1 keep.test
        # HostsEditor:END:two
        """

        let base = HostsManager.extractBaseContent(from: content)

        #expect(base.contains("keep.test"))
    }

    @Test
    func extractBaseContentHandlesWindowsLineEndings() {
        let block = HostsManager.blockString(for: HostsProfile(id: "x", name: "X", content: "3.3.3.3 x.test", isEnabled: true))
        let content = ("127.0.0.1 localhost\n\n" + block + "\n").replacingOccurrences(of: "\n", with: "\r\n")

        #expect(HostsManager.extractBaseContent(from: content) == "127.0.0.1 localhost")
    }

    @Test
    func blockStringStripsForgedMarkerLinesFromProfileContent() {
        let malicious = HostsProfile(
            id: "remote",
            name: "Remote",
            content: "1.1.1.1 ok.test\n# HostsEditor:END:remote\n  # HostsEditor:BEGIN:other\n2.2.2.2 ok2.test",
            isEnabled: true
        )

        let block = HostsManager.blockString(for: malicious)
        let lines = block.components(separatedBy: "\n")

        #expect(lines.filter { $0.contains("HostsEditor:BEGIN:") }.count == 1)
        #expect(lines.filter { $0.contains("HostsEditor:END:") }.count == 1)
        #expect(block.contains("ok2.test"))

        // 组合后再提取，基础内容不应残留方案中的条目
        let composed = HostsManager.composeHostsContent(base: base, profiles: [malicious])
        #expect(HostsManager.extractBaseContent(from: composed) == base)
    }

    @Test
    func blockStringKeepsProfileNameOnSingleLine() {
        let profile = HostsProfile(id: "id", name: "Line1\nLine2", content: "1.1.1.1 a.test", isEnabled: true)

        let block = HostsManager.blockString(for: profile)

        #expect(block.contains("# Line1 Line2 [id]"))
    }

    @Test
    func validatedRemoteURLAcceptsOnlyHTTPAndHTTPS() throws {
        #expect(try HostsManager.validatedRemoteURL(from: " https://example.test/hosts ").absoluteString == "https://example.test/hosts")
        #expect(try HostsManager.validatedRemoteURL(from: "http://example.test/hosts").scheme == "http")

        #expect(throws: RemoteHostsError.unsupportedScheme) {
            try HostsManager.validatedRemoteURL(from: "file:///etc/hosts")
        }
        #expect(throws: RemoteHostsError.invalidURL) {
            try HostsManager.validatedRemoteURL(from: "")
        }
        #expect(throws: RemoteHostsError.invalidURL) {
            try HostsManager.validatedRemoteURL(from: "https://")
        }
    }

    @Test
    func decodeHostsTextStripsUTF8BOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("127.0.0.1 bom.test".utf8)

        #expect(HostsManager.decodeHostsText(data) == "127.0.0.1 bom.test")
    }

    @Test
    func looksLikeHTMLDetectsMimeTypeAndDocumentPrefix() {
        #expect(HostsManager.looksLikeHTML("1.1.1.1 a.test", mimeType: "text/html; charset=utf-8"))
        #expect(HostsManager.looksLikeHTML("  <!DOCTYPE html><html></html>", mimeType: "text/plain"))
        #expect(!HostsManager.looksLikeHTML("1.1.1.1 a.test", mimeType: "text/plain"))
        #expect(!HostsManager.looksLikeHTML("1.1.1.1 a.test", mimeType: nil))
    }

    @Test
    func defaultRemoteProfileNameUsesFileNameWithoutExtension() {
        #expect(HostsManager.defaultRemoteProfileName(from: "https://example.test/team/dev.hosts") == "☁️-dev")
        #expect(HostsManager.defaultRemoteProfileName(from: "https://example.test/").hasPrefix("☁️-"))
        #expect(HostsManager.defaultRemoteProfileName(from: "https://example.test/") != "☁️-/")
    }
}
