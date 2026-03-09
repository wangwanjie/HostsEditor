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
    @Published private(set) var appliedProfileId: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    private let userDefaultsKey = "HostsEditorProfiles"
    private let appliedProfileIdKey = "HostsEditorAppliedProfileId"

    private init() {
        loadProfiles()
        loadAppliedProfileId()
    }

    // MARK: - Persistence

    func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([HostsProfile].self, from: data) else {
            profiles = [HostsProfile(name: "默认", content: "")]
            return
        }
        profiles = decoded
    }

    func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadAppliedProfileId() {
        appliedProfileId = UserDefaults.standard.string(forKey: appliedProfileIdKey)
    }

    private func setAppliedProfileId(_ id: String?) {
        appliedProfileId = id
        UserDefaults.standard.set(id, forKey: appliedProfileIdKey)
    }

    // MARK: - Profile CRUD

    func addProfile(_ profile: HostsProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    func updateProfile(id: String, name: String? = nil, content: String?) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { profiles[idx].name = name }
        if let content = content { profiles[idx].content = content }
        saveProfiles()
    }

    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id }
        if appliedProfileId == id { setAppliedProfileId(nil) }
        saveProfiles()
    }

    func profile(for id: String) -> HostsProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - System hosts

    func refreshSystemContent() async {
        do {
            currentSystemContent = try await PrivilegedHostsWriter.shared.readHosts()
            errorMessage = nil
        } catch {
            errorMessage = "读取系统 hosts 失败: \(error.localizedDescription)"
            currentSystemContent = """
            # 无法读取系统 hosts
            # 请先安装帮助程序：点击「应用到系统」时会提示输入密码安装
            # 或确保 HostsEditorHelper 已正确安装
            """
        }
    }

    /// 将指定方案应用到系统 /etc/hosts
    func applyProfile(id: String) async {
        guard let profile = profile(for: id) else {
            errorMessage = "未找到该方案"
            return
        }
        await applyContent(profile.content, profileId: id)
    }

    /// 将当前编辑内容应用到系统（不绑定方案 ID）
    func applyContent(_ content: String, profileId: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await PrivilegedHostsWriter.shared.writeHosts(content: content)
            if let id = profileId { setAppliedProfileId(id) }
            else { setAppliedProfileId(nil) }
            currentSystemContent = content
        } catch {
            errorMessage = "写入失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Remote

    func fetchRemoteHosts(urlString: String) async -> Result<String, Error> {
        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "HostsEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"]))
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "HostsEditor", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解码为 UTF-8"]))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    func addRemoteProfile(name: String, urlString: String) async {
        switch await fetchRemoteHosts(urlString: urlString) {
        case .success(let content):
            let profile = HostsProfile(
                name: name,
                content: content,
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
