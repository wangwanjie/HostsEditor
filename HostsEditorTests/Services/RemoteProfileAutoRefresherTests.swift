import Foundation
import Testing
@testable import HostsEditor

@MainActor
@Suite(.serialized)
struct RemoteProfileAutoRefresherTests {
    private func makeComponents(lastUpdated: Date) throws -> (RemoteProfileAutoRefresher, HostsManager, AppSettings) {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in .init(body: Data("10.0.0.1 refreshed.test".utf8)) }
        let database = try AppDatabase.inMemory()
        try database.saveProfiles([
            HostsProfile(id: "r", name: "Remote", content: "old", isRemote: true, remoteURL: "https://example.test/hosts", lastUpdated: lastUpdated),
        ])
        let writer = FakePrivilegedHostsWriter(hostsContent: "127.0.0.1 localhost")
        let manager = HostsManager(
            database: database,
            privilegedWriter: writer,
            systemHostsReader: { writer.hostsContent },
            urlSession: StubURLProtocol.makeSession(),
            notificationCenter: NotificationCenter()
        )
        let settings = AppSettings(database: database)
        return (RemoteProfileAutoRefresher(manager: manager, settings: settings, checkInterval: 3600), manager, settings)
    }

    @Test
    func refreshIsSkippedWhenAutoRefreshIsOff() async throws {
        let (refresher, manager, settings) = try makeComponents(lastUpdated: Date(timeIntervalSince1970: 0))
        settings.remoteRefreshInterval = .off

        let count = await refresher.refreshIfNeeded()

        #expect(count == 0)
        #expect(manager.profile(for: "r")?.content == "old")
    }

    @Test
    func refreshUpdatesExpiredRemoteProfiles() async throws {
        let now = Date()
        let (refresher, manager, settings) = try makeComponents(lastUpdated: now.addingTimeInterval(-2 * 3600))
        settings.remoteRefreshInterval = .hourly

        let count = await refresher.refreshIfNeeded(now: now)

        #expect(count == 1)
        #expect(manager.profile(for: "r")?.content == "10.0.0.1 refreshed.test")
    }

    @Test
    func timerIsScheduledOnlyWhileIntervalIsEnabled() async throws {
        let (refresher, _, settings) = try makeComponents(lastUpdated: Date())
        refresher.start()
        defer { refresher.stop() }

        try waitUntil(description: "timer stays unscheduled when off") { !refresher.isScheduled }

        settings.remoteRefreshInterval = .daily
        try waitUntil(description: "timer scheduled after enabling") { refresher.isScheduled }

        settings.remoteRefreshInterval = .off
        try waitUntil(description: "timer removed after disabling") { !refresher.isScheduled }
    }

    @Test
    func intervalSecondsMatchOptions() {
        #expect(RemoteRefreshInterval.off.seconds == nil)
        #expect(RemoteRefreshInterval.hourly.seconds == TimeInterval(3_600))
        #expect(RemoteRefreshInterval.everySixHours.seconds == TimeInterval(21_600))
        #expect(RemoteRefreshInterval.daily.seconds == TimeInterval(86_400))
    }
}
