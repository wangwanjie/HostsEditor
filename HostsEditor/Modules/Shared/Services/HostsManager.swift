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

/// 远程方案拉取过程中的业务错误
enum RemoteHostsError: Error, LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme
    case httpStatus(Int)
    case htmlResponse
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.tr("hosts.error.invalid_url")
        case .unsupportedScheme:
            return L10n.tr("hosts.error.unsupported_scheme")
        case .httpStatus(let code):
            return L10n.tr("hosts.error.http_status", code)
        case .htmlResponse:
            return L10n.tr("hosts.error.html_response")
        case .invalidEncoding:
            return L10n.tr("hosts.error.invalid_utf8")
        }
    }
}

extension Notification.Name {
    static let hostsEditorHelperInterventionRequired = Notification.Name("HostsEditorHelperInterventionRequired")
}

@MainActor
final class HostsManager: ObservableObject {
    static let shared: HostsManager = AppEnvironment.isScreenshotDemo ? DemoData.makeManager() : HostsManager()

    static let managedBlockBeginPrefix = "# HostsEditor:BEGIN:"
    static let managedBlockEndPrefix = "# HostsEditor:END:"
    static let systemHostsPath = "/etc/hosts"
    /// 远程拉取的超时时间
    static let remoteFetchTimeout: TimeInterval = 30

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
    private let privilegedWriter: PrivilegedHostsWriting
    private let systemHostsReader: () throws -> String
    private let urlSession: URLSession
    private let backupStore: HostsBackupStore?
    private let notificationCenter: NotificationCenter
    private var pendingPrivilegedOperation: PendingPrivilegedOperation?
    /// 串行化所有特权写入，避免快速连续操作时多个写入交错、回滚互相覆盖
    private var lastPrivilegedTask: Task<Void, Never>?
    private var runningPrivilegedOperations = 0

    /// 系统 hosts 中不属于任何方案的原始部分
    private(set) var baseSystemContent: String = ""

    init(
        database: AppDatabase? = nil,
        privilegedWriter: PrivilegedHostsWriting? = nil,
        systemHostsReader: (() throws -> String)? = nil,
        urlSession: URLSession? = nil,
        backupStore: HostsBackupStore? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.database = database ?? .shared
        self.privilegedWriter = privilegedWriter ?? PrivilegedHostsWriter.shared
        self.systemHostsReader = systemHostsReader ?? {
            try String(contentsOfFile: HostsManager.systemHostsPath, encoding: .utf8)
        }
        self.urlSession = urlSession ?? Self.makeDefaultURLSession()
        self.notificationCenter = notificationCenter
        // 只有正式运行且使用默认数据库时才启用默认备份目录，测试不会往用户目录写文件
        let usesDefaultBackupStore = database == nil && !AppEnvironment.isRunningTests
        self.backupStore = backupStore ?? (usesDefaultBackupStore ? HostsBackupStore.default : nil)
        loadProfiles()
        baseSystemContent = loadBaseSystemContent()
    }

    private static func makeDefaultURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = remoteFetchTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
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
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedProfile = profiles[idx]
        if let name {
            updatedProfile.name = name
        }
        if let content {
            updatedProfile.content = content
        }
        profiles[idx] = updatedProfile
        saveProfiles()
    }

    /// 复制一个方案（远程方案复制后成为可编辑的本地方案），插入到原方案之后，默认不启用
    @discardableResult
    func duplicateProfile(id: String) -> HostsProfile? {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let source = profiles[idx]
        let copy = HostsProfile(
            name: L10n.tr("hosts.duplicate_name", source.name),
            content: source.content,
            isEnabled: false
        )
        profiles.insert(copy, at: idx + 1)
        saveProfiles()
        return copy
    }

    /// 从本地文件导入为新的本地方案，方案名取文件名（去掉后缀）
    @discardableResult
    func importProfile(fromFileURL url: URL) throws -> HostsProfile {
        let data = try Data(contentsOf: url)
        guard let content = Self.decodeHostsText(data) else {
            throw RemoteHostsError.invalidEncoding
        }
        let baseName = url.deletingPathExtension().lastPathComponent
        let name = baseName.isEmpty ? L10n.tr("main.new_profile_name") : baseName
        let profile = HostsProfile(name: name, content: content)
        addProfile(profile)
        errorMessage = nil
        return profile
    }

    func deleteProfile(id: String) async -> Bool {
        let previousProfiles = profiles
        let updatedProfiles = previousProfiles.filter { $0.id != id }
        guard updatedProfiles.count != previousProfiles.count else {
            return false
        }

        // 被删除的方案未启用时，系统 hosts 不受影响，直接删除即可
        let deletedProfileWasApplied = previousProfiles.contains { $0.id == id && $0.isEnabled }
        if !deletedProfileWasApplied {
            profiles = updatedProfiles
            saveProfiles()
            pendingPrivilegedOperation = nil
            errorMessage = nil
            return true
        }

        do {
            try await applyComposedHosts { profiles in
                profiles.filter { $0.id != id }
            }
            profiles.removeAll { $0.id == id }
            saveProfiles()
            return true
        } catch {
            queuePendingPrivilegedOperation(.deleteProfile(id: id), for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.delete_profile"))
            return false
        }
    }

    func setProfileEnabled(id: String, enabled: Bool) async {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard profiles[idx].isEnabled != enabled else {
            return
        }

        profiles[idx].isEnabled = enabled
        saveProfiles()
        do {
            try await applyComposedHosts()
        } catch {
            // 只回滚当前方案的启用状态，避免整体快照覆盖期间发生的其他修改
            if let currentIdx = profiles.firstIndex(where: { $0.id == id }) {
                profiles[currentIdx].isEnabled = !enabled
                saveProfiles()
            }
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
            let content = try systemHostsReader()
            updateSystemSnapshot(with: content)
            errorMessage = nil
        } catch {
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.read_system_hosts"))
        }
    }

    /// 将内容直接写入系统 hosts（用于「系统」项编辑后保存）
    func writeSystemContent(_ content: String) async {
        do {
            try await performPrivilegedOperation {
                let verifiedContent = try await self.writeAndVerifyHosts(content)
                self.updateSystemSnapshot(with: verifiedContent)
            }
            pendingPrivilegedOperation = nil
            errorMessage = nil
        } catch {
            queuePendingPrivilegedOperation(.writeSystemContent(content), for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.write_system_hosts"))
        }
    }

    // MARK: - Compose & Write

    /// 将 base 内容与所有启用方案的块组合后写入 /etc/hosts
    @discardableResult
    func writeComposedHosts() async -> Bool {
        do {
            try await applyComposedHosts()
            return true
        } catch {
            queuePendingPrivilegedOperation(.writeComposedHosts, for: error)
            handlePrivilegedOperationError(error, operation: L10n.tr("operation.apply_profiles"))
            return false
        }
    }

    func composeHostsContent() -> String {
        Self.composeHostsContent(base: baseSystemContent, profiles: profiles)
    }

    /// 组合最终写入 /etc/hosts 的内容：基础内容 + 各启用方案的标记块，末尾保留换行
    static func composeHostsContent(base: String, profiles: [HostsProfile]) -> String {
        var parts: [String] = []
        if !base.isEmpty {
            parts.append(base)
        }
        for profile in profiles where profile.isEnabled {
            let trimmed = profile.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            parts.append(blockString(for: profile))
        }
        guard !parts.isEmpty else {
            return ""
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func blockString(for profile: HostsProfile) -> String {
        let sep = "# -------------------------------------------------------------------------------"
        let body = sanitizedBlockBody(profile.content)
        // 方案名只保留单行，避免换行破坏标记块结构
        let displayName = profile.name.components(separatedBy: .newlines).joined(separator: " ")
        return [
            "\(managedBlockBeginPrefix)\(profile.id)",
            sep,
            "# \(displayName) [\(profile.id)]",
            sep,
            body,
            "\(managedBlockEndPrefix)\(profile.id)"
        ].joined(separator: "\n")
    }

    /// 去掉方案内容中伪造的 BEGIN/END 标记行，防止远程内容或复制粘贴的文本破坏块解析
    static func sanitizedBlockBody(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .newlines)
        let lines = trimmed.components(separatedBy: "\n").filter { line in
            let normalized = line.trimmingCharacters(in: .whitespaces)
            return !normalized.hasPrefix(managedBlockBeginPrefix) && !normalized.hasPrefix(managedBlockEndPrefix)
        }
        return lines.joined(separator: "\n")
    }

    /// 从 hosts 内容中剥离所有由本应用管理的块，返回原始基础内容
    static func extractBaseContent(from content: String) -> String {
        var result = content.replacingOccurrences(of: "\r\n", with: "\n")
        // 匹配 BEGIN…END 块（含前导空行），并要求 END 的 id 与 BEGIN 一致
        let pattern = "\\n?# HostsEditor:BEGIN:([^\\n]+?)[ \\t]*\\n[\\s\\S]*?# HostsEditor:END:\\1[ \\t]*(\\n|$)"
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

    private func updateSystemSnapshot(with content: String) {
        currentSystemContent = content
        let base = Self.extractBaseContent(from: content)
        baseSystemContent = base
        persistBaseSystemContent(base)
    }

    // MARK: - Remote

    /// 校验远程地址，只允许 http / https
    static func validatedRemoteURL(from urlString: String) throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw RemoteHostsError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw RemoteHostsError.unsupportedScheme
        }
        guard url.host?.isEmpty == false else {
            throw RemoteHostsError.invalidURL
        }
        return url
    }

    /// 解码 hosts 文本：优先 UTF-8（去掉 BOM），失败再尝试 Latin-1
    static func decodeHostsText(_ data: Data) -> String? {
        var payload = data
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if payload.starts(with: bom) {
            payload = payload.dropFirst(bom.count)
        }
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        return String(data: payload, encoding: .isoLatin1)
    }

    /// 判断响应是否为 HTML 页面（常见于地址填错、被重定向到登录页等情况）
    static func looksLikeHTML(_ text: String, mimeType: String?) -> Bool {
        if let mimeType, mimeType.lowercased().contains("html") {
            return true
        }
        let head = text.prefix(512).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    func fetchRemoteHosts(urlString: String) async -> Result<String, Error> {
        do {
            let url = try Self.validatedRemoteURL(from: urlString)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.remoteFetchTimeout)
            request.setValue("HostsEditor", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await urlSession.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw RemoteHostsError.httpStatus(httpResponse.statusCode)
            }
            guard let text = Self.decodeHostsText(data) else {
                throw RemoteHostsError.invalidEncoding
            }
            if Self.looksLikeHTML(text, mimeType: response.mimeType) {
                throw RemoteHostsError.htmlResponse
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    /// 从 URL 生成远程方案默认名称：☁️-文件名（去后缀）
    static func defaultRemoteProfileName(from urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "☁️-\(L10n.tr("hosts.remote_default_name"))"
        }
        let filename = url.lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        if nameWithoutExt.isEmpty || nameWithoutExt == "/" {
            return "☁️-\(L10n.tr("hosts.remote_default_name"))"
        }
        return "☁️-\(nameWithoutExt)"
    }

    /// 添加远程方案；同一 URL 已存在时改为刷新已有方案。返回对应方案 id，失败返回 nil
    @discardableResult
    func addRemoteProfile(urlString: String) async -> String? {
        let normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = profiles.first(where: { $0.isRemote && $0.remoteURL == normalizedURL }) {
            let refreshed = await refreshRemoteProfile(id: existing.id)
            return refreshed ? existing.id : nil
        }

        let name = Self.defaultRemoteProfileName(from: normalizedURL)
        switch await fetchRemoteHosts(urlString: normalizedURL) {
        case .success(let content):
            let profile = HostsProfile(
                name: name,
                content: content,
                isEnabled: false,
                isRemote: true,
                remoteURL: normalizedURL,
                lastUpdated: Date()
            )
            addProfile(profile)
            errorMessage = nil
            return profile.id
        case .failure(let error):
            errorMessage = L10n.tr("hosts.error.remote_fetch", error.localizedDescription)
            return nil
        }
    }

    /// 刷新远程方案；内容变化且方案启用时自动重新写入系统 hosts。返回是否整体成功
    @discardableResult
    func refreshRemoteProfile(id: String) async -> Bool {
        guard let url = profile(for: id)?.remoteURL else {
            return false
        }

        switch await fetchRemoteHosts(urlString: url) {
        case .success(let content):
            // 拉取期间方案可能已被删除，重新定位
            guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
                return false
            }
            var updated = profiles[idx]
            let contentChanged = updated.content != content
            updated.content = content
            updated.lastUpdated = Date()
            profiles[idx] = updated
            saveProfiles()

            if contentChanged && updated.isEnabled {
                // 写入失败时 writeComposedHosts 已设置错误信息，这里不能再清空
                return await writeComposedHosts()
            }
            errorMessage = nil
            return true
        case .failure(let error):
            errorMessage = L10n.tr("hosts.error.remote_refresh", error.localizedDescription)
            return false
        }
    }

    /// 刷新所有超过指定时长未更新的远程方案，返回实际尝试刷新的数量
    @discardableResult
    func refreshStaleRemoteProfiles(olderThan interval: TimeInterval, now: Date = Date()) async -> Int {
        let staleIds = profiles
            .filter { profile in
                guard profile.isRemote, profile.remoteURL != nil else {
                    return false
                }
                guard let lastUpdated = profile.lastUpdated else {
                    return true
                }
                return now.timeIntervalSince(lastUpdated) >= interval
            }
            .map(\.id)

        for id in staleIds {
            await refreshRemoteProfile(id: id)
        }
        return staleIds.count
    }

    // MARK: - Helper install

    func enableHelper() async throws {
        try await privilegedWriter.enableHelper()
    }

    func uninstallHelperAndWait() async throws {
        try await privilegedWriter.uninstallHelperAndWait()
        pendingPrivilegedOperation = nil
    }

    func reinstallHelper() async throws {
        try await privilegedWriter.reinstallHelper()
    }

    func retryPendingPrivilegedOperationIfNeeded() async {
        guard let pendingPrivilegedOperation else {
            return
        }

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
        privilegedWriter.isHelperInstalled
    }

    var isHelperExplicitlyDisabled: Bool {
        privilegedWriter.isHelperExplicitlyDisabled
    }

    var hasRegisteredHelper: Bool {
        privilegedWriter.hasRegisteredHelper
    }

    var backupDirectoryURL: URL? {
        backupStore?.directoryURL
    }

    private func handlePrivilegedOperationError(_ error: Error, operation: String) {
        errorMessage = L10n.tr("common.operation_failed", operation, error.localizedDescription)

        guard let kind = helperInterventionKind(for: error) else {
            return
        }
        notificationCenter.post(
            name: .hostsEditorHelperInterventionRequired,
            object: nil,
            userInfo: [
                "kind": kind.rawValue,
                "operation": operation,
            ]
        )
    }

    private func queuePendingPrivilegedOperation(_ operation: PendingPrivilegedOperation, for error: Error) {
        guard helperInterventionKind(for: error) != nil else {
            return
        }
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

    // MARK: - Privileged write pipeline

    /// 按提交顺序串行执行特权操作，并维护 isLoading 状态
    private func performPrivilegedOperation(_ operation: @escaping () async throws -> Void) async throws {
        let previousTask = lastPrivilegedTask
        runningPrivilegedOperations += 1
        isLoading = true

        let task = Task { @MainActor () async throws -> Void in
            await previousTask?.value
            try await operation()
        }
        lastPrivilegedTask = Task { @MainActor in
            _ = try? await task.value
        }

        defer {
            runningPrivilegedOperations -= 1
            isLoading = runningPrivilegedOperations > 0
        }
        try await task.value
    }

    private func applyComposedHosts(
        transform: @escaping ([HostsProfile]) -> [HostsProfile] = { $0 }
    ) async throws {
        try await performPrivilegedOperation {
            // 写入前重新读取系统 hosts，避免覆盖掉外部工具在此期间写入的基础内容
            if let latestContent = try? self.systemHostsReader() {
                self.updateSystemSnapshot(with: latestContent)
            }

            // 在真正执行时才组合内容，保证排队期间的最新方案状态都能生效
            let composed = Self.composeHostsContent(base: self.baseSystemContent, profiles: transform(self.profiles))
            let verifiedContent = try await self.writeAndVerifyHosts(composed)
            self.currentSystemContent = verifiedContent
            self.pendingPrivilegedOperation = nil
            self.errorMessage = nil
        }
    }

    private func writeAndVerifyHosts(_ content: String) async throws -> String {
        // 写入前先备份当前系统 hosts，备份失败不阻断写入
        if let backupStore, let currentContent = try? systemHostsReader() {
            backupStore.backup(content: currentContent)
        }

        try await privilegedWriter.writeHosts(content: content)
        let actualContent = try systemHostsReader()
        guard actualContent == content else {
            throw HostsWriteVerificationError.contentMismatch
        }
        return actualContent
    }
}
