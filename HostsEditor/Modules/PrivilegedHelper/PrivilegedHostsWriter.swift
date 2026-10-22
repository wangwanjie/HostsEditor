//
//  PrivilegedHostsWriter.swift
//  HostsEditor
//
//  通过 SMAppService 注册 LaunchDaemon，并通过 XPC 写入 /etc/hosts。
//

import Foundation
import ServiceManagement

private let helperLabel = "cn.vanjay.HostsEditorHelper"
private let daemonPlistName = "cn.vanjay.HostsEditorHelper.plist"
private let helperExecutableName = "HostsEditorHelper"
private let helperProgramIdentifier = "Contents/MacOS/\(helperExecutableName)"
private let helperExplicitlyDisabledKey = "HostsEditorHelperExplicitlyDisabled"

enum PrivilegedHostsError: Error, LocalizedError {
    case requiresApproval
    case disabledByUser
    case registrationFailed(String)
    case repairRequired(String)
    case connectionFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return L10n.tr("helper.alert.approval.message")
        case .disabledByUser:
            return L10n.tr("helper.alert.disabled.title")
        case .registrationFailed(let message):
            return message.isEmpty ? L10n.tr("helper.alert.enable_failed.title") : message
        case .repairRequired(let message):
            return message.isEmpty ? L10n.tr("helper.alert.repair_required.title") : message
        case .connectionFailed:
            return L10n.tr("helper.error.connection_failed")
        case .timeout:
            return L10n.tr("helper.error.timeout")
        }
    }
}

/// 解析 `launchctl print` 输出，用于判断 Helper 是否需要修复（internal 便于单元测试）
struct HelperLaunchdState {
    let rawOutput: String

    var programIdentifier: String? {
        value(after: "program identifier = ")?.components(separatedBy: " (mode:").first
    }

    var needsLWCRUpdate: Bool {
        rawOutput.contains("needs LWCR update")
    }

    var isSpawnFailed: Bool {
        rawOutput.contains("job state = spawn failed") || rawOutput.contains("last exit code = 78: EX_CONFIG")
    }

    /// 只有输出中确实存在 program identifier 且与预期不一致时才算路径不匹配；
    /// 部分系统版本的输出不含该字段，不能因此反复要求修复
    var hasProgramPathMismatch: Bool {
        guard let programIdentifier else {
            return false
        }
        return programIdentifier != helperProgramIdentifier
    }

    var shouldForceRepair: Bool {
        needsLWCRUpdate || hasProgramPathMismatch || isSpawnFailed
    }

    var recoveryMessage: String {
        if hasProgramPathMismatch {
            return L10n.tr("helper.error.recovery_path_mismatch")
        }

        if needsLWCRUpdate {
            return L10n.tr("helper.error.recovery_lwcr_update")
        }

        return L10n.tr("helper.error.recovery_spawn_failed")
    }

    private func value(after prefix: String) -> String? {
        for line in rawOutput.split(whereSeparator: \.isNewline) {
            let line = String(line).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { continue }
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }
}

/// 保证多个并发回调中只有第一个能“认领”结果
private nonisolated final class ResumeOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else {
            return false
        }
        claimed = true
        return true
    }
}

/// HostsManager 依赖的特权写入能力，便于在测试中替换为假实现
protocol PrivilegedHostsWriting: AnyObject {
    var daemonStatus: SMAppService.Status { get }
    var isHelperInstalled: Bool { get }
    var isHelperExplicitlyDisabled: Bool { get }
    var hasRegisteredHelper: Bool { get }
    func writeHosts(content: String) async throws
    func enableHelper() async throws
    func uninstallHelperAndWait() async throws
    func reinstallHelper() async throws
}

final class PrivilegedHostsWriter: PrivilegedHostsWriting {

    static let shared = PrivilegedHostsWriter()

    private init() {}

    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: daemonPlistName)
    }

    var daemonStatus: SMAppService.Status {
        daemonService.status
    }

    var hasRegisteredHelper: Bool {
        switch daemonStatus {
        case .notRegistered, .notFound:
            return false
        case .enabled, .requiresApproval:
            return true
        @unknown default:
            return true
        }
    }

    var isHelperInstalled: Bool {
        daemonStatus == .enabled
    }

    var isHelperExplicitlyDisabled: Bool {
        UserDefaults.standard.bool(forKey: helperExplicitlyDisabledKey)
    }

    func needsRepairAfterLaunch() async -> Bool {
        guard daemonStatus == .enabled else { return false }
        guard let state = await currentLaunchdState() else { return false }
        return state.shouldForceRepair
    }

    func enableHelper() async throws {
        setHelperExplicitlyDisabled(false)
        try await prepareHelper(forceRepair: false)
    }

    func repairHelper() async throws {
        setHelperExplicitlyDisabled(false)
        try await prepareHelper(forceRepair: true)
    }

    func uninstallHelperAndWait() async throws {
        let helperReachable = await isHelperReachable(timeout: 0.5)

        guard hasRegisteredHelper || helperReachable else {
            setHelperExplicitlyDisabled(true)
            return
        }

        try await unregisterHelper()

        guard await waitForHelperUnregistered() else {
            throw PrivilegedHostsError.registrationFailed(L10n.tr("helper.error.uninstall_in_progress"))
        }

        setHelperExplicitlyDisabled(true)
    }

    func reinstallHelper() async throws {
        try await repairHelper()
    }

    func writeHosts(content: String) async throws {
        try await prepareHelper(forceRepair: false)
        // 写入包含 DNS 缓存刷新，给出比读取更宽松的超时
        try await performHelperCall(timeout: 15) { proxy, complete in
            proxy.writeHosts(content: content) { success, error in
                if success {
                    complete(.success(()))
                } else {
                    complete(.failure(error ?? PrivilegedHostsError.connectionFailed))
                }
            }
        }
    }

    func readHosts() async throws -> String {
        try await prepareHelper(forceRepair: false)
        return try await performHelperCall(timeout: 5) { proxy, complete in
            proxy.readHosts { content, error in
                if let content {
                    complete(.success(content))
                } else {
                    complete(.failure(error ?? PrivilegedHostsError.connectionFailed))
                }
            }
        }
    }

    /// 统一封装一次 XPC 调用：错误回调、业务回调与超时三者中只有第一个结果生效，避免 continuation 被重复 resume
    private func performHelperCall<T>(
        timeout: TimeInterval,
        _ body: @escaping (HostsHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = ResumeOnceGate()

            func resumeOnce(_ result: Result<T, Error>) {
                guard gate.tryClaim() else {
                    return
                }
                continuation.resume(with: result)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(.failure(PrivilegedHostsError.timeout))
            }

            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                resumeOnce(.failure(error))
            }) as? HostsHelperProtocol else {
                resumeOnce(.failure(PrivilegedHostsError.connectionFailed))
                return
            }

            body(proxy, resumeOnce)
        }
    }

    private func makeConnection() -> NSXPCConnection? {
        let conn = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        conn.resume()
        return conn
    }

    private func prepareHelper(forceRepair: Bool) async throws {
        switch daemonStatus {
        case .enabled:
            let launchdState = await currentLaunchdState()

            if forceRepair {
                try await repairRegisteredHelper()
            } else {
                if let launchdState, launchdState.shouldForceRepair {
                    throw PrivilegedHostsError.repairRequired(launchdState.recoveryMessage)
                }

                if await waitForHelperReachable() {
                    return
                }
            }
        case .notRegistered, .notFound:
            if isHelperExplicitlyDisabled {
                throw PrivilegedHostsError.disabledByUser
            }
            try registerHelper()
        case .requiresApproval:
            throw PrivilegedHostsError.requiresApproval
        @unknown default:
            throw PrivilegedHostsError.registrationFailed(L10n.tr("helper.error.unknown_status"))
        }

        if daemonStatus == .requiresApproval {
            throw PrivilegedHostsError.requiresApproval
        }

        guard daemonStatus == .enabled else {
            throw PrivilegedHostsError.registrationFailed(L10n.tr("helper.error.not_enabled"))
        }

        guard await waitForHelperReachable() else {
            if let launchdState = await currentLaunchdState(), launchdState.shouldForceRepair {
                throw PrivilegedHostsError.repairRequired(launchdState.recoveryMessage)
            }
            throw PrivilegedHostsError.connectionFailed
        }
    }

    private func registerHelper() throws {
        let service = daemonService

        do {
            try service.register()
            setHelperExplicitlyDisabled(false)
        } catch {
            if service.status == .enabled || service.status == .requiresApproval {
                if service.status == .enabled {
                    setHelperExplicitlyDisabled(false)
                }
                return
            }

            throw mapRegistrationError(error as NSError)
        }
    }

    private func unregisterHelper() async throws {
        let service = daemonService
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            service.unregister { [weak self] error in
                guard let self else {
                    continuation.resume()
                    return
                }

                guard let nsError = error as NSError? else {
                    continuation.resume()
                    return
                }

                if nsError.code == kSMErrorJobNotFound {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: self.mapRegistrationError(nsError))
                }
            }
        }
    }

    private func repairRegisteredHelper() async throws {
        if hasRegisteredHelper {
            try await unregisterHelper()
            _ = await waitForHelperUnregistered()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        try registerHelper()
    }

    private func waitForHelperReachable(attempts: Int = 20) async -> Bool {
        for attempt in 0..<attempts {
            if await isHelperReachable() {
                return true
            }

            guard attempt < attempts - 1 else { continue }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        return false
    }

    private func waitForHelperUnregistered(attempts: Int = 12) async -> Bool {
        for attempt in 0..<attempts {
            let status = daemonStatus
            let launchdState = await currentLaunchdState()

            if status == .notRegistered || status == .notFound || launchdState == nil {
                return true
            }

            guard attempt < attempts - 1 else { continue }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        let status = daemonStatus
        let launchdState = await currentLaunchdState()
        return status == .notRegistered || status == .notFound || launchdState == nil
    }

    private func isHelperReachable(timeout: TimeInterval = 1.5) async -> Bool {
        guard let conn = makeConnection() else { return false }
        defer { conn.invalidate() }

        return await withCheckedContinuation { continuation in
            let gate = ResumeOnceGate()

            func resumeOnce(_ value: Bool) {
                guard gate.tryClaim() else {
                    return
                }
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                resumeOnce(false)
            } as? HostsHelperProtocol

            guard let proxy else {
                resumeOnce(false)
                return
            }

            proxy.ping { success in
                resumeOnce(success)
            }
        }
    }

    private nonisolated func currentLaunchdState() async -> HelperLaunchdState? {
        await Task.detached(priority: .utility) {
            Self.readLaunchdState()
        }.value
    }

    private static nonisolated func readLaunchdState() -> HelperLaunchdState? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/cn.vanjay.HostsEditorHelper"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return nil
        }

        return HelperLaunchdState(rawOutput: output)
    }

    private func mapRegistrationError(_ error: NSError?) -> PrivilegedHostsError {
        if daemonStatus == .requiresApproval || error?.code == kSMErrorLaunchDeniedByUser {
            return .requiresApproval
        }

        let message = error?.localizedDescription ?? L10n.tr("helper.alert.enable_failed.title")
        return .registrationFailed(message)
    }

    private func setHelperExplicitlyDisabled(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: helperExplicitlyDisabledKey)
    }
}
