import Foundation
import Testing
@testable import HostsEditor

@MainActor
@Suite(.serialized)
struct HostsManagerRemoteTests {
    private func makeManager(profiles: [HostsProfile] = []) throws -> (HostsManager, FakePrivilegedHostsWriter) {
        StubURLProtocol.reset()
        let database = try AppDatabase.inMemory()
        try database.saveProfiles(profiles)
        let writer = FakePrivilegedHostsWriter(hostsContent: "127.0.0.1 localhost")
        let manager = HostsManager(
            database: database,
            privilegedWriter: writer,
            systemHostsReader: { writer.hostsContent },
            urlSession: StubURLProtocol.makeSession(),
            notificationCenter: NotificationCenter()
        )
        return (manager, writer)
    }

    @Test
    func addRemoteProfileStoresFetchedContentAndReturnsItsId() async throws {
        let (manager, _) = try makeManager()
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.1 remote.test".utf8)) }

        let id = try #require(await manager.addRemoteProfile(urlString: "https://example.test/team.hosts"))

        let profile = try #require(manager.profile(for: id))
        #expect(profile.isRemote)
        #expect(profile.name == "☁️-team")
        #expect(profile.content == "10.0.0.1 remote.test")
        #expect(profile.lastUpdated != nil)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func addingSameRemoteURLRefreshesExistingProfileInsteadOfDuplicating() async throws {
        let existing = HostsProfile(id: "r", name: "Remote", content: "old", isRemote: true, remoteURL: "https://example.test/hosts")
        let (manager, _) = try makeManager(profiles: [existing])
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.2 new.test".utf8)) }

        let id = await manager.addRemoteProfile(urlString: "https://example.test/hosts")

        #expect(id == "r")
        #expect(manager.profiles.filter(\.isRemote).count == 1)
        #expect(manager.profile(for: "r")?.content == "10.0.0.2 new.test")
    }

    @Test
    func nonSuccessStatusCodeIsReportedAsFailure() async throws {
        let (manager, _) = try makeManager()
        StubURLProtocol.responder = { _ in .init(statusCode: 404, body: Data("not found".utf8)) }

        let id = await manager.addRemoteProfile(urlString: "https://example.test/missing")

        #expect(id == nil)
        #expect(manager.profiles.allSatisfy { !$0.isRemote })
        #expect(manager.errorMessage?.contains("404") == true)
    }

    @Test
    func htmlResponseIsRejected() async throws {
        let (manager, _) = try makeManager()
        StubURLProtocol.responder = { _ in .init(mimeType: "text/html", body: Data("<html>login</html>".utf8)) }

        let result = await manager.fetchRemoteHosts(urlString: "https://example.test/login")

        guard case .failure(let error) = result else {
            Issue.record("Expected HTML response to be rejected")
            return
        }
        #expect(error as? RemoteHostsError == .htmlResponse)
    }

    @Test
    func unsupportedSchemeFailsWithoutNetworkRequest() async throws {
        let (manager, _) = try makeManager()

        let result = await manager.fetchRemoteHosts(urlString: "file:///etc/hosts")

        guard case .failure(let error) = result else {
            Issue.record("Expected file URL to be rejected")
            return
        }
        #expect(error as? RemoteHostsError == .unsupportedScheme)
        #expect(StubURLProtocol.requestCount == 0)
    }

    @Test
    func refreshingEnabledRemoteProfileRewritesSystemHostsWhenContentChanges() async throws {
        let remote = HostsProfile(id: "r", name: "Remote", content: "10.0.0.1 old.test", isEnabled: true, isRemote: true, remoteURL: "https://example.test/hosts")
        let (manager, writer) = try makeManager(profiles: [remote])
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.1 new.test".utf8)) }

        let succeeded = await manager.refreshRemoteProfile(id: "r")

        #expect(succeeded)
        #expect(writer.hostsContent.contains("new.test"))
        #expect(manager.errorMessage == nil)
    }

    @Test
    func refreshingWithUnchangedContentDoesNotRewriteSystemHosts() async throws {
        let remote = HostsProfile(id: "r", name: "Remote", content: "10.0.0.1 same.test", isEnabled: true, isRemote: true, remoteURL: "https://example.test/hosts")
        let (manager, writer) = try makeManager(profiles: [remote])
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.1 same.test".utf8)) }

        let succeeded = await manager.refreshRemoteProfile(id: "r")

        #expect(succeeded)
        #expect(writer.writtenContents.isEmpty)
        #expect(manager.profile(for: "r")?.lastUpdated != nil)
    }

    @Test
    func refreshKeepsWriteErrorVisibleInsteadOfClearingIt() async throws {
        let remote = HostsProfile(id: "r", name: "Remote", content: "10.0.0.1 old.test", isEnabled: true, isRemote: true, remoteURL: "https://example.test/hosts")
        let (manager, writer) = try makeManager(profiles: [remote])
        writer.errorToThrow = PrivilegedHostsError.timeout
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.1 new.test".utf8)) }

        let succeeded = await manager.refreshRemoteProfile(id: "r")

        #expect(!succeeded)
        #expect(manager.errorMessage != nil)
    }

    @Test
    func refreshStaleRemoteProfilesOnlyRefreshesExpiredOnes() async throws {
        let now = Date()
        let stale = HostsProfile(id: "stale", name: "Stale", content: "a", isRemote: true, remoteURL: "https://example.test/stale", lastUpdated: now.addingTimeInterval(-7200))
        let fresh = HostsProfile(id: "fresh", name: "Fresh", content: "b", isRemote: true, remoteURL: "https://example.test/fresh", lastUpdated: now.addingTimeInterval(-60))
        let local = HostsProfile(id: "local", name: "Local", content: "c")
        let (manager, _) = try makeManager(profiles: [stale, fresh, local])
        StubURLProtocol.responder = { request in .init(body: Data("10.0.0.9 \(request.url?.lastPathComponent ?? "").test".utf8)) }

        let refreshedCount = await manager.refreshStaleRemoteProfiles(olderThan: 3600, now: now)

        #expect(refreshedCount == 1)
        #expect(manager.profile(for: "stale")?.content == "10.0.0.9 stale.test")
        #expect(manager.profile(for: "fresh")?.content == "b")
        #expect(StubURLProtocol.requestCount == 1)
    }
}
