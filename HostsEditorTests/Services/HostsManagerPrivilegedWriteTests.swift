import Foundation
import Testing
@testable import HostsEditor

@MainActor
@Suite(.serialized)
struct HostsManagerPrivilegedWriteTests {
    nonisolated private static let base = "127.0.0.1 localhost"

    private func makeManager(
        profiles: [HostsProfile],
        hosts: String = HostsManagerPrivilegedWriteTests.base,
        notificationCenter: NotificationCenter = NotificationCenter(),
        backupStore: HostsBackupStore? = nil
    ) throws -> (HostsManager, FakePrivilegedHostsWriter) {
        let database = try AppDatabase.inMemory()
        try database.saveProfiles(profiles)
        let writer = FakePrivilegedHostsWriter(hostsContent: hosts)
        let manager = HostsManager(
            database: database,
            privilegedWriter: writer,
            systemHostsReader: { writer.hostsContent },
            urlSession: StubURLProtocol.makeSession(),
            backupStore: backupStore,
            notificationCenter: notificationCenter
        )
        return (manager, writer)
    }

    @Test
    func enablingProfileWritesComposedHostsAndKeepsBaseContent() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test")
        let (manager, writer) = try makeManager(profiles: [profile])

        await manager.setProfileEnabled(id: "dev", enabled: true)

        #expect(writer.hostsContent.hasPrefix(Self.base))
        #expect(writer.hostsContent.contains("# HostsEditor:BEGIN:dev"))
        #expect(manager.currentSystemContent == writer.hostsContent)
        #expect(manager.profile(for: "dev")?.isEnabled == true)
        #expect(manager.errorMessage == nil)
        #expect(manager.isLoading == false)
    }

    @Test
    func settingSameEnabledStateDoesNotWrite() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test", isEnabled: false)
        let (manager, writer) = try makeManager(profiles: [profile])

        await manager.setProfileEnabled(id: "dev", enabled: false)

        #expect(writer.writtenContents.isEmpty)
    }

    @Test
    func failedWriteRollsBackOnlyTheToggledProfileAndReportsError() async throws {
        let target = HostsProfile(id: "target", name: "Target", content: "10.0.0.1 t.test")
        let other = HostsProfile(id: "other", name: "Other", content: "10.0.0.2 o.test")
        let (manager, writer) = try makeManager(profiles: [target, other])
        writer.errorToThrow = PrivilegedHostsError.timeout

        await manager.setProfileEnabled(id: "target", enabled: true)

        #expect(manager.profile(for: "target")?.isEnabled == false)
        #expect(manager.errorMessage != nil)
        #expect(writer.hostsContent == Self.base)
        #expect(manager.isLoading == false)
    }

    @Test
    func composingRereadsSystemHostsSoExternalEditsAreNotLost() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test")
        let (manager, writer) = try makeManager(profiles: [profile])
        await manager.refreshSystemContent()

        // 模拟其他工具在应用运行期间修改了 /etc/hosts
        writer.hostsContent = Self.base + "\n10.9.9.9 external.test\n"

        await manager.setProfileEnabled(id: "dev", enabled: true)

        #expect(writer.hostsContent.contains("external.test"))
        #expect(writer.hostsContent.contains("dev.test"))
        #expect(manager.baseSystemContent.contains("external.test"))
    }

    @Test
    func verificationMismatchReportsErrorAndRequestsRepair() async throws {
        let center = NotificationCenter()
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test")
        let (manager, writer) = try makeManager(profiles: [profile], notificationCenter: center)
        writer.tamper = { _ in "tampered" }

        let receivedKind = ValueBox<String>()
        let token = center.addObserver(forName: .hostsEditorHelperInterventionRequired, object: nil, queue: nil) { notification in
            receivedKind.value = notification.userInfo?["kind"] as? String
        }
        defer { center.removeObserver(token) }

        await manager.setProfileEnabled(id: "dev", enabled: true)

        #expect(manager.errorMessage != nil)
        #expect(manager.profile(for: "dev")?.isEnabled == false)
        #expect(receivedKind.value == HelperInterventionKind.repair.rawValue)
    }

    @Test
    func concurrentTogglesAreSerializedAndBothApplied() async throws {
        let first = HostsProfile(id: "first", name: "First", content: "10.0.0.1 first.test")
        let second = HostsProfile(id: "second", name: "Second", content: "10.0.0.2 second.test")
        let (manager, writer) = try makeManager(profiles: [first, second])
        writer.writeDelayNanoseconds = 50_000_000

        async let enableFirst: Void = manager.setProfileEnabled(id: "first", enabled: true)
        async let enableSecond: Void = manager.setProfileEnabled(id: "second", enabled: true)
        _ = await (enableFirst, enableSecond)

        #expect(writer.writtenContents.count == 2)
        #expect(writer.hostsContent.contains("first.test"))
        #expect(writer.hostsContent.contains("second.test"))
        #expect(manager.isLoading == false)
    }

    @Test
    func deletingEnabledProfileRemovesItsBlockFromSystemHosts() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test")
        let (manager, writer) = try makeManager(profiles: [profile])
        await manager.setProfileEnabled(id: "dev", enabled: true)

        let deleted = await manager.deleteProfile(id: "dev")

        #expect(deleted)
        #expect(manager.profile(for: "dev") == nil)
        #expect(!writer.hostsContent.contains("dev.test"))
        #expect(writer.hostsContent.hasPrefix(Self.base))
    }

    @Test
    func deletingDisabledProfileDoesNotTouchSystemHosts() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test")
        let (manager, writer) = try makeManager(profiles: [profile])

        let deleted = await manager.deleteProfile(id: "dev")

        #expect(deleted)
        #expect(writer.writtenContents.isEmpty)
    }

    @Test
    func failedDeleteKeepsProfile() async throws {
        let profile = HostsProfile(id: "dev", name: "Dev", content: "10.0.0.1 dev.test", isEnabled: true)
        let (manager, writer) = try makeManager(profiles: [profile])
        writer.errorToThrow = PrivilegedHostsError.timeout

        let deleted = await manager.deleteProfile(id: "dev")

        #expect(!deleted)
        #expect(manager.profile(for: "dev") != nil)
        #expect(manager.errorMessage != nil)
    }

    @Test
    func writingSystemContentUpdatesBaseAndBacksUpPreviousContent() async throws {
        let directory = try makeTemporaryDirectory("HostsManagerBackup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HostsBackupStore(directoryURL: directory)
        let (manager, writer) = try makeManager(profiles: [], backupStore: store)

        await manager.writeSystemContent("127.0.0.1 localhost\n10.1.1.1 manual.test\n")

        #expect(writer.hostsContent.contains("manual.test"))
        #expect(manager.baseSystemContent.contains("manual.test"))
        let backups = store.backupFiles()
        #expect(backups.count == 1)
        #expect(try String(contentsOf: try #require(backups.first), encoding: .utf8) == Self.base)
    }

    @Test
    func duplicateProfileInsertsDisabledLocalCopyAfterSource() throws {
        let remote = HostsProfile(id: "r", name: "Remote", content: "1.1.1.1 r.test", isEnabled: true, isRemote: true, remoteURL: "https://example.test/r")
        let tail = HostsProfile(id: "tail", name: "Tail")
        let (manager, _) = try makeManager(profiles: [remote, tail])

        let copy = try #require(manager.duplicateProfile(id: "r"))

        #expect(manager.profiles.map(\.id) == ["r", copy.id, "tail"])
        #expect(copy.content == remote.content)
        #expect(copy.isRemote == false)
        #expect(copy.isEnabled == false)
        #expect(copy.name.contains("Remote"))
    }

    @Test
    func importProfileReadsFileAndUsesFileNameAsProfileName() throws {
        let directory = try makeTemporaryDirectory("HostsImport")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("staging.hosts")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("10.0.0.5 staging.test\n".utf8)).write(to: fileURL)
        let (manager, _) = try makeManager(profiles: [])

        let profile = try manager.importProfile(fromFileURL: fileURL)

        #expect(profile.name == "staging")
        #expect(profile.content == "10.0.0.5 staging.test\n")
        #expect(manager.profile(for: profile.id) != nil)
    }
}
