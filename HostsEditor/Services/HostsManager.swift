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
        L10n.tr("hosts.error.write_verification")
    }
}

extension Notification.Name {
    static let hostsEditorHelperInterventionRequired = Notification.Name("HostsEditorHelperInterventionRequired")
}

@MainActor
final class HostsManager: ObservableObject {
    static let shared = HostsManager()

    private enum PendingPrivilegedOperation {
        case writeSystemContent(String)
        case writeComposedHosts
        case setProfileEnabled(id: String, enabled: Bool)
        case deleteProfile(id: String)
    }

    @Published private(set) var profiles: [HostsProfile] = []
    @Published private(set) var currentSystemContent: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    private let database: AppDatabase
    private var pendingPrivilegedOperation: PendingPrivilegedOperation?

    /// 系统 hosts 中不属于任何方案的原始部分
    private(set) var baseSystemContent: String = ""

    init(database: AppDatabase? = nil) {
        self.database = database ?? .shared
        loadProfiles()
        baseSystemContent = loadBaseSystemContent()
    }

    // MARK: - Persistence

    func loadProfiles() {
        guard let loadedProfiles = try? database.loadProfiles(),
              !loadedProfiles.isEmpty else {
            profiles = [HostsProfile(name: L10n.tr("hosts.default_profile_name"), content: "")]
            return
        }
        profiles = loadedProfiles
    }

    func saveProfiles() {
        do {
            try database.saveProfiles(profiles)
        } catch {
            NSLog("Failed to persist profiles: %@", String(describing: error))
        }
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

    func deleteProfile(id: String) async -> Bool {
        let previousProfiles = profiles
        let updatedProfiles = previousProfiles.filter { $0.id != id }
        guard updatedProfiles.count != previousProfiles.count else { return false }

        let currentComposedHosts = composeHostsContent(from: previousProfiles)
        let updatedComposedHosts = composeHostsContent(from: updatedProfiles)

        if currentComposedHosts == updatedComposedHosts {
            profiles = updatedProfiles
            saveProfiles()
            pendingPrivilegedOperation = nil
            errorMessage = nil
            return true
        }

        do {
            try await applyComposedHosts(using: updatedProfiles)
            profiles = updatedProfiles
            saveProfiles()
            return true
        } catch {
            queuePendingPrivilegedOperation(.deleteProfile(id: id), for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.delete_profile"))
            return false
        }
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
            queuePendingPrivilegedOperation(.setProfileEnabled(id: id, enabled: enabled), for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.apply_profiles"))
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
            persistBaseSystemContent(base)
            errorMessage = nil
        } catch {
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.read_system_hosts"))
        }
    }

    /// 将内容直接写入系统 hosts（用于「系统」项编辑后保存）
    func writeSystemContent(_ content: String) async {
        do {
            let verifiedContent = try await writeAndVerifyHosts(content)
            currentSystemContent = verifiedContent
            let base = Self.extractBaseContent(from: verifiedContent)
            baseSystemContent = base
            persistBaseSystemContent(base)
            pendingPrivilegedOperation = nil
            errorMessage = nil
        } catch {
            queuePendingPrivilegedOperation(.writeSystemContent(content), for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.write_system_hosts"))
        }
    }

    // MARK: - Compose & Write

    /// 将 base 内容与所有启用方案的块组合后写入 /etc/hosts
    func writeComposedHosts() async {
        do {
            try await applyComposedHosts()
        } catch {
            queuePendingPrivilegedOperation(.writeComposedHosts, for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.apply_profiles"))
        }
    }

    func composeHostsContent() -> String {
        composeHostsContent(from: profiles)
    }

    private func composeHostsContent(from profiles: [HostsProfile]) -> String {
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

    private func loadBaseSystemContent() -> String {
        do {
            if case .string(let storedBaseContent)? = try database.settingValue(.baseSystemContent) {
                return storedBaseContent
            }
        } catch {
            NSLog("Failed to load base system content: %@", String(describing: error))
        }
        return ""
    }

    private func persistBaseSystemContent(_ content: String) {
        do {
            try database.saveSetting(.baseSystemContent, value: .string(content))
        } catch {
            NSLog("Failed to persist base system content: %@", String(describing: error))
        }
    }

    // MARK: - Remote

    func fetchRemoteHosts(urlString: String) async -> Result<String, Error> {
        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "HostsEditor", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: L10n.tr("hosts.error.invalid_url")]))
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "HostsEditor", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: L10n.tr("hosts.error.invalid_utf8")]))
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// 从 URL 生成远程方案默认名称：☁️-文件名（去后缀）
    static func defaultRemoteProfileName(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "☁️-\(L10n.tr("hosts.remote_default_name"))" }
        let filename = url.lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        return nameWithoutExt.isEmpty ? "☁️-\(L10n.tr("hosts.remote_default_name"))" : "☁️-\(nameWithoutExt)"
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
            errorMessage = L10n.tr("hosts.error.remote_fetch", error.localizedDescription)
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
            errorMessage = L10n.tr("hosts.error.remote_refresh", error.localizedDescription)
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
        pendingPrivilegedOperation = nil
    }

    func uninstallHelperAndWait() async throws {
        try await PrivilegedHostsWriter.shared.uninstallHelperAndWait()
        pendingPrivilegedOperation = nil
    }

    func reinstallHelper() async throws {
        try await PrivilegedHostsWriter.shared.reinstallHelper()
    }

    func retryPendingPrivilegedOperationIfNeeded() async {
        guard let pendingPrivilegedOperation else { return }

        self.pendingPrivilegedOperation = nil
        errorMessage = nil

        switch pendingPrivilegedOperation {
        case .writeSystemContent(let content):
            await writeSystemContent(content)
        case .writeComposedHosts:
            await writeComposedHosts()
        case .setProfileEnabled(let id, let enabled):
            await setProfileEnabled(id: id, enabled: enabled)
        case .deleteProfile(let id):
            _ = await deleteProfile(id: id)
        }
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
        errorMessage = L10n.tr("common.operation_failed", operation, error.localizedDescription)

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

    private func queuePendingPrivilegedOperation(_ operation: PendingPrivilegedOperation, for error: Error) {
        guard helperInterventionKind(for: error) != nil else { return }
        pendingPrivilegedOperation = operation
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
        try await applyComposedHosts(using: profiles)
    }

    private func applyComposedHosts(using profiles: [HostsProfile]) async throws {
        isLoading = true
        defer { isLoading = false }

        let composed = composeHostsContent(from: profiles)
        let verifiedContent = try await writeAndVerifyHosts(composed)
        currentSystemContent = verifiedContent
        pendingPrivilegedOperation = nil
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
