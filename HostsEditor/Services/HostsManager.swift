//
//  HostsManager.swift
//  HostsEditor
//

import Foundation
import AppKit
import Combine

@MainActor
final class HostsManager: ObservableObject {
    static let shared = HostsManager()

    @Published private(set) var profiles: [HostsProfile] = []
    @Published private(set) var currentSystemContent: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    private let profilesKey = "HostsEditorProfiles"
    private let baseContentKey = "HostsEditorBaseContent"

    /// 系统 hosts 中不属于任何方案的原始部分
    private(set) var baseSystemContent: String = ""

    private init() {
        loadProfiles()
        baseSystemContent = UserDefaults.standard.string(forKey: baseContentKey) ?? ""
    }

    // MARK: - Persistence

    func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([HostsProfile].self, from: data) else {
            profiles = [HostsProfile(name: "默认", content: "")]
            return
        }
        profiles = decoded
    }

    func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: profilesKey)
    }

    // MARK: - Profile CRUD

    func addProfile(_ profile: HostsProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    func updateProfile(id: String, name: String? = nil, content: String? = nil) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { profiles[idx].name = name }
        if let content = content { profiles[idx].content = content }
        saveProfiles()
    }

    func deleteProfile(id: String) async {
        profiles.removeAll { $0.id == id }
        saveProfiles()
        await writeComposedHosts()
    }

    func setProfileEnabled(id: String, enabled: Bool) async {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].isEnabled = enabled
        saveProfiles()
        await writeComposedHosts()
    }

    func profile(for id: String) -> HostsProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - System hosts

    func refreshSystemContent() async {
        do {
            let content = try await PrivilegedHostsWriter.shared.readHosts()
            currentSystemContent = content
            let base = Self.extractBaseContent(from: content)
            baseSystemContent = base
            UserDefaults.standard.set(base, forKey: baseContentKey)
            errorMessage = nil
        } catch {
            errorMessage = "读取系统 hosts 失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Compose & Write

    /// 将 base 内容与所有启用方案的块组合后写入 /etc/hosts
    func writeComposedHosts() async {
        isLoading = true
        defer { isLoading = false }
        let composed = composeHostsContent()
        do {
            try await PrivilegedHostsWriter.shared.writeHosts(content: composed)
            currentSystemContent = composed
            errorMessage = nil
        } catch {
            errorMessage = "写入失败: \(error.localizedDescription)"
        }
    }

    func composeHostsContent() -> String {
        var parts: [String] = []
        if !baseSystemContent.isEmpty {
            parts.append(baseSystemContent)
        }
        for profile in profiles where profile.isEnabled {
            let trimmed = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            parts.append(Self.blockString(for: profile))
        }
        return parts.joined(separator: "\n\n")
    }

    static func blockString(for profile: HostsProfile) -> String {
        let sep = "# -------------------------------------------------------------------------------"
        let trimmed = profile.content.trimmingCharacters(in: .newlines)
        return [
            "# HostsEditor:BEGIN:\(profile.id)",
            sep,
            "# \(profile.name) [\(profile.id)]",
            sep,
            trimmed,
            "# HostsEditor:END:\(profile.id)"
        ].joined(separator: "\n")
    }

    /// 从 hosts 内容中剥离所有由本应用管理的块，返回原始基础内容
    static func extractBaseContent(from content: String) -> String {
        var result = content
        // 匹配 BEGIN…END 块（含前后空行）
        let pattern = "\n?# HostsEditor:BEGIN:[^\\n]+\\n[\\s\\S]*?# HostsEditor:END:[^\\n]+(\\n|$)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // 合并连续空行
        let cleanPattern = "\\n{3,}"
        if let regex = try? NSRegularExpression(pattern: cleanPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Remote

    func fetchRemoteHosts(urlString: String) async -> Result<String, Error> {
        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "HostsEditor", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "无效的 URL"]))
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "HostsEditor", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "无法解码为 UTF-8"]))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// 从 URL 生成远程方案默认名称：☁️-文件名（去后缀）
    static func defaultRemoteProfileName(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "☁️-hosts" }
        let filename = url.lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        return nameWithoutExt.isEmpty ? "☁️-hosts" : "☁️-\(nameWithoutExt)"
    }

    func addRemoteProfile(urlString: String) async {
        let name = Self.defaultRemoteProfileName(from: urlString)
        switch await fetchRemoteHosts(urlString: urlString) {
        case .success(let content):
            let profile = HostsProfile(
                name: name,
                content: content,
                isEnabled: false,
                isRemote: true,
                remoteURL: urlString,
                lastUpdated: Date()
            )
            addProfile(profile)
            errorMessage = nil
        case .failure(let error):
            errorMessage = "拉取远程配置失败: \(error.localizedDescription)"
        }
    }

    func refreshRemoteProfile(id: String) async {
        guard let idx = profiles.firstIndex(where: { $0.id == id }),
              let url = profiles[idx].remoteURL else { return }
        switch await fetchRemoteHosts(urlString: url) {
        case .success(let content):
            profiles[idx].content = content
            profiles[idx].lastUpdated = Date()
            saveProfiles()
            if profiles[idx].isEnabled {
                await writeComposedHosts()
            }
            errorMessage = nil
        case .failure(let error):
            errorMessage = "刷新失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helper install

    func installHelperIfNeeded() -> Error? {
        PrivilegedHostsWriter.shared.installHelperIfNeeded()
    }

    var isHelperInstalled: Bool {
        PrivilegedHostsWriter.shared.isHelperInstalled
    }
}
