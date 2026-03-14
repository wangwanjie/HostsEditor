//
//  HostsManager.swift
//  HostsEditor
//

import Foundation
import AppKit
import Combine

enum HelperInterventionKind: String {
    case install
    case approval
    case repair
}

enum HostsWriteVerificationError: Error, LocalizedError {
    case contentMismatch

    var errorDescription: String? {
        "系统 hosts 写入后校验失败，文件内容未更新"
    }
}

extension Notification.Name {
    static let hostsEditorHelperInterventionRequired = Notification.Name("HostsEditorHelperInterventionRequired")
}

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
            profiles = [HostsProfile(name: "点击可更改配置名称", content: "")]
            return
        }
        profiles = decoded.isEmpty ? [HostsProfile(name: "点击可更改配置名称", content: "")] : decoded
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
        let previousProfiles = profiles
        profiles[idx].isEnabled = enabled
        saveProfiles()
        do {
            try await applyComposedHosts()
        } catch {
            profiles = previousProfiles
            saveProfiles()
            handlePrivilegedOperationError(error, operation: "应用配置")
        }
    }

    func profile(for id: String) -> HostsProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - System hosts

    func refreshSystemContent() async {
        do {
            let content = try readSystemHostsContent()
            currentSystemContent = content
            let base = Self.extractBaseContent(from: content)
            baseSystemContent = base
            UserDefaults.standard.set(base, forKey: baseContentKey)
            errorMessage = nil
        } catch {
            handlePrivilegedOperationError(error, operation: "读取系统 hosts")
        }
    }

    /// 将内容直接写入系统 hosts（用于「系统」项编辑后保存）
    func writeSystemContent(_ content: String) async {
        do {
            let verifiedContent = try await writeAndVerifyHosts(content)
            currentSystemContent = verifiedContent
            let base = Self.extractBaseContent(from: verifiedContent)
            baseSystemContent = base
            UserDefaults.standard.set(base, forKey: baseContentKey)
            errorMessage = nil
        } catch {
            handlePrivilegedOperationError(error, operation: "写入系统 hosts")
        }
    }

    // MARK: - Compose & Write

    /// 将 base 内容与所有启用方案的块组合后写入 /etc/hosts
    func writeComposedHosts() async {
        do {
            try await applyComposedHosts()
        } catch {
            handlePrivilegedOperationError(error, operation: "应用配置")
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
            var updated = profiles[idx]
            updated.content = content
            updated.lastUpdated = Date()
            profiles[idx] = updated
            saveProfiles()
            if updated.isEnabled {
                await writeComposedHosts()
            }
            errorMessage = nil
        case .failure(let error):
            errorMessage = "刷新失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helper install

    func installHelperIfNeeded() async throws {
        try await PrivilegedHostsWriter.shared.installHelperIfNeeded()
    }

    func enableHelper() async throws {
        try await PrivilegedHostsWriter.shared.enableHelper()
    }

    func uninstallHelper() async throws {
        try await PrivilegedHostsWriter.shared.uninstallHelper()
    }

    func uninstallHelperAndWait() async throws {
        try await PrivilegedHostsWriter.shared.uninstallHelperAndWait()
    }

    func reinstallHelper() async throws {
        try await PrivilegedHostsWriter.shared.reinstallHelper()
    }

    var isHelperInstalled: Bool {
        PrivilegedHostsWriter.shared.isHelperInstalled
    }

    var isHelperExplicitlyDisabled: Bool {
        PrivilegedHostsWriter.shared.isHelperExplicitlyDisabled
    }

    var hasRegisteredHelper: Bool {
        PrivilegedHostsWriter.shared.hasRegisteredHelper
    }

    private func handlePrivilegedOperationError(_ error: Error, operation: String) {
        errorMessage = "\(operation)失败: \(error.localizedDescription)"

        guard let kind = helperInterventionKind(for: error) else { return }
        NotificationCenter.default.post(
            name: .hostsEditorHelperInterventionRequired,
            object: nil,
            userInfo: [
                "kind": kind.rawValue,
                "operation": operation,
            ]
        )
    }

    private func helperInterventionKind(for error: Error) -> HelperInterventionKind? {
        if let privilegedError = error as? PrivilegedHostsError {
            switch privilegedError {
            case .requiresApproval:
                return .approval
            case .disabledByUser:
                return .install
            case .registrationFailed:
                return .install
            case .repairRequired:
                return .repair
            case .connectionFailed:
                return .repair
            case .timeout:
                return nil
            }
        }

        if error is HostsWriteVerificationError {
            return .repair
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           let code = POSIXErrorCode(rawValue: Int32(nsError.code)),
           code == .EPERM || code == .EACCES {
            return .approval
        }
        return nil
    }

    private func readSystemHostsContent() throws -> String {
        try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
    }

    private func applyComposedHosts() async throws {
        isLoading = true
        defer { isLoading = false }

        let composed = composeHostsContent()
        let verifiedContent = try await writeAndVerifyHosts(composed)
        currentSystemContent = verifiedContent
        errorMessage = nil
    }

    private func writeAndVerifyHosts(_ content: String) async throws -> String {
        try await PrivilegedHostsWriter.shared.writeHosts(content: content)
        let actualContent = try readSystemHostsContent()
        guard actualContent == content else {
            throw HostsWriteVerificationError.contentMismatch
        }
        return actualContent
    }
}
