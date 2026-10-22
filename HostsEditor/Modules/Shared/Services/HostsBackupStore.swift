//
//  HostsBackupStore.swift
//  HostsEditor
//
//  每次写入系统 hosts 前，把当时的内容备份到 Application Support，便于误操作后手动恢复。
//

import Foundation

final class HostsBackupStore {
    static let defaultMaximumBackupCount = 30
    static let filePrefix = "hosts-"
    static let fileExtension = "txt"

    /// 默认备份目录：~/Library/Application Support/HostsEditor/Backups
    static let `default`: HostsBackupStore? = {
        guard let appSupportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let directory = appSupportURL
            .appendingPathComponent("HostsEditor", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        return HostsBackupStore(directoryURL: directory)
    }()

    let directoryURL: URL
    let maximumBackupCount: Int
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        directoryURL: URL,
        maximumBackupCount: Int = HostsBackupStore.defaultMaximumBackupCount,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.maximumBackupCount = max(1, maximumBackupCount)
        self.fileManager = fileManager
        self.now = now
    }

    /// 写入一份备份；内容与最近一份备份相同则跳过。返回新备份文件地址，跳过或失败返回 nil
    @discardableResult
    func backup(content: String) -> URL? {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if let latest = backupFiles().first,
               let latestContent = try? String(contentsOf: latest, encoding: .utf8),
               latestContent == content {
                return nil
            }

            let fileURL = nextBackupFileURL()
            try Data(content.utf8).write(to: fileURL, options: .atomic)
            pruneOldBackups()
            return fileURL
        } catch {
            NSLog("Failed to back up hosts content: %@", String(describing: error))
            return nil
        }
    }

    /// 按时间从新到旧排列的备份文件
    func backupFiles() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        // 文件名包含定长时间戳，按文件名倒序即按时间倒序
        return urls
            .filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func nextBackupFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = formatter.string(from: now())

        var candidate = directoryURL.appendingPathComponent("\(Self.filePrefix)\(stamp).\(Self.fileExtension)")
        var suffix = 1
        // 同一毫秒内多次备份时追加序号，避免覆盖
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(Self.filePrefix)\(stamp)-\(suffix).\(Self.fileExtension)")
            suffix += 1
        }
        return candidate
    }

    private func pruneOldBackups() {
        let files = backupFiles()
        guard files.count > maximumBackupCount else {
            return
        }
        for url in files.dropFirst(maximumBackupCount) {
            try? fileManager.removeItem(at: url)
        }
    }
}
