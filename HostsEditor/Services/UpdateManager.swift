//
//  UpdateManager.swift
//  HostsEditor
//

import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

struct ReleaseVersion: Comparable {
    let rawValue: String
    private let components: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        self.components = Self.parse(rawValue)
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    private static func parse(_ rawValue: String) -> [Int] {
        var sanitized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("v") || sanitized.hasPrefix("V") {
            sanitized.removeFirst()
        }

        let values = sanitized
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }

        let trimmed = values.reversed().drop(while: { $0 == 0 }).reversed()
        return Array(trimmed)
    }
}

@MainActor
final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    private let lastUpdateCheckKey = "HostsEditorLastUpdateCheckDate"

    #if canImport(Sparkle)
    private var sparkleUpdaterController: SPUStandardUpdaterController?
    #endif

    private override init() {}

    func configure() {
        #if canImport(Sparkle)
        guard sparkleUpdaterController == nil, isSparkleConfigured else { return }
        sparkleUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    func scheduleBackgroundUpdateCheck() {
        #if canImport(Sparkle)
        if sparkleUpdaterController != nil {
            return
        }
        #endif

        let interval: TimeInterval = 24 * 60 * 60
        if let lastCheck = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < interval {
            return
        }

        Task { [weak self] in
            await self?.checkGitHubLatestRelease(interactive: false)
        }
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        if let sparkleUpdaterController {
            sparkleUpdaterController.checkForUpdates(nil)
            return
        }
        #endif

        Task { [weak self] in
            await self?.checkGitHubLatestRelease(interactive: true)
        }
    }

    func openGitHubHomepage() {
        guard let url = repositoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var repositoryURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "HostsEditorGitHubURL") as? String else { return nil }
        return URL(string: raw)
    }

    private var latestReleaseAPIURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "HostsEditorGitHubLatestReleaseAPIURL") as? String else { return nil }
        return URL(string: raw)
    }

    #if canImport(Sparkle)
    private var isSparkleConfigured: Bool {
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !feedURL.isEmpty && !publicKey.isEmpty
    }
    #endif

    private func checkGitHubLatestRelease(interactive: Bool) async {
        guard let latestReleaseAPIURL else {
            if interactive {
                presentFailureAlert(message: "未配置 GitHub Releases 更新地址。")
            }
            return
        }

        do {
            let release = try await fetchLatestRelease(from: latestReleaseAPIURL)
            UserDefaults.standard.set(Date(), forKey: lastUpdateCheckKey)
            presentReleaseResult(release, interactive: interactive)
        } catch {
            if interactive {
                presentFailureAlert(message: error.localizedDescription)
            }
        }
    }

    private func fetchLatestRelease(from url: URL) async throws -> GitHubRelease {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HostsEditor", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw NSError(
                domain: "HostsEditor.UpdateManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "检查更新失败，GitHub 返回了异常状态。"]
            )
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func presentReleaseResult(_ release: GitHubRelease, interactive: Bool) {
        let currentVersion = ReleaseVersion(currentAppVersion)
        let latestVersion = ReleaseVersion(release.tagName)

        guard latestVersion > currentVersion else {
            if interactive {
                let alert = NSAlert()
                alert.messageText = "当前已是最新版本"
                alert.informativeText = "当前版本 \(currentAppVersion)，GitHub Releases 最新版本 \(release.tagName)。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.tagName)"
        if let name = release.name, !name.isEmpty {
            alert.informativeText = "当前版本 \(currentAppVersion)。GitHub Releases 上已有新版本“\(name)”，是否前往查看？"
        } else {
            alert.informativeText = "当前版本 \(currentAppVersion)。GitHub Releases 上已有新版本，是否前往查看？"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private var currentAppVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}
