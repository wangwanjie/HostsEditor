import Foundation
import Testing
@testable import HostsEditor

@MainActor
struct HostsBackupStoreTests {
    /// 每次调用推进 1 秒的时钟，保证备份文件名单调递增
    private final class SteppingClock {
        private var current = Date(timeIntervalSince1970: 1_800_000_000)

        func next() -> Date {
            current = current.addingTimeInterval(1)
            return current
        }
    }

    @Test
    func backupWritesFileAndSkipsIdenticalConsecutiveContent() throws {
        let directory = try makeTemporaryDirectory("BackupStore")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = SteppingClock()
        let store = HostsBackupStore(directoryURL: directory, now: clock.next)

        let first = store.backup(content: "127.0.0.1 localhost")
        let duplicate = store.backup(content: "127.0.0.1 localhost")
        let second = store.backup(content: "127.0.0.1 localhost\n10.0.0.1 a.test")

        #expect(first != nil)
        #expect(duplicate == nil)
        #expect(second != nil)
        #expect(store.backupFiles().count == 2)
        #expect(store.backupFiles().first?.lastPathComponent == second?.lastPathComponent)
    }

    @Test
    func backupPrunesOldestFilesBeyondLimit() throws {
        let directory = try makeTemporaryDirectory("BackupStorePrune")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = SteppingClock()
        let store = HostsBackupStore(directoryURL: directory, maximumBackupCount: 3, now: clock.next)

        for index in 0..<5 {
            store.backup(content: "content-\(index)")
        }

        let files = store.backupFiles()
        #expect(files.count == 3)
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(contents == ["content-4", "content-3", "content-2"])
    }

    @Test
    func backupFilesIgnoresUnrelatedFiles() throws {
        let directory = try makeTemporaryDirectory("BackupStoreFilter")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let store = HostsBackupStore(directoryURL: directory)

        #expect(store.backupFiles().isEmpty)
    }
}
