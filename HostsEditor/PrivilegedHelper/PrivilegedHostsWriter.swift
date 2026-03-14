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
            return "需要在“系统设置 -> 通用 -> 登录项与扩展程序”中允许后台帮助程序"
        case .disabledByUser:
            return "后台帮助程序已停用，请在“帮助”菜单中重新启用后再写入 hosts"
        case .registrationFailed(let message):
            return message.isEmpty ? "后台帮助程序注册失败" : message
        case .repairRequired(let message):
            return message.isEmpty ? "后台帮助程序需要修复" : message
        case .connectionFailed:
            return "无法连接帮助程序"
        case .timeout:
            return "连接超时"
        }
    }
}

private struct HelperLaunchdState {
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

    var shouldForceRepair: Bool {
        needsLWCRUpdate || programIdentifier != helperProgramIdentifier || isSpawnFailed
    }

    var recoveryMessage: String {
        if let programIdentifier, programIdentifier != helperProgramIdentifier {
            return "系统当前记录的后台帮助程序路径与当前安装包不一致。请先清理旧登录项或后台任务记录，再重新运行当前构建后点击“启用或修复后台帮助程序”。"
        }

        if needsLWCRUpdate {
            return "macOS 仍在使用旧的后台任务注册记录。请先停用后台帮助程序，再重新启用；若仍失败，请清理旧登录项/后台任务记录后重试。"
        }

        return "后台帮助程序已注册，但 macOS 拉起该进程时仍然失败。请在“帮助”菜单中手动执行一次“启用或修复后台帮助程序”。"
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

final class PrivilegedHostsWriter {

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

    func installHelperIfNeeded() async throws {
        try await prepareHelper(forceRepair: false)
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
            throw PrivilegedHostsError.registrationFailed("后台帮助程序仍在卸载中，请稍后再试")
        }

        setHelperExplicitlyDisabled(true)
    }

    func uninstallHelper() async throws {
        guard hasRegisteredHelper else { return }
        try await unregisterHelper()
    }

    func reinstallHelper() async throws {
        try await repairHelper()
    }

    func writeHosts(content: String) async throws {
        try await prepareHelper(forceRepair: false)
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] error in
                conn?.invalidate()
                continuation.resume(throwing: error)
            } as! HostsHelperProtocol
            proxy.writeHosts(content: content) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PrivilegedHostsError.connectionFailed)
                }
            }
        }
    }

    func readHosts() async throws -> String {
        try await prepareHelper(forceRepair: false)
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var finished = false
            let lock = NSLock()

            func resumeOnce(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true

                switch result {
                case .success(let content):
                    continuation.resume(returning: content)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                resumeOnce(.failure(PrivilegedHostsError.timeout))
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] error in
                conn?.invalidate()
                resumeOnce(.failure(error))
            } as! HostsHelperProtocol

            proxy.readHosts { content, error in
                if let content {
                    resumeOnce(.success(content))
                } else {
                    resumeOnce(.failure(error ?? PrivilegedHostsError.connectionFailed))
                }
            }
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
            throw PrivilegedHostsError.registrationFailed("检测到未知的后台帮助程序状态")
        }

        if daemonStatus == .requiresApproval {
            throw PrivilegedHostsError.requiresApproval
        }

        guard daemonStatus == .enabled else {
            throw PrivilegedHostsError.registrationFailed("后台帮助程序未处于可用状态")
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
            var finished = false
            let lock = NSLock()

            func resumeOnce(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                resumeOnce(false)
            } as? HostsHelperProtocol

            proxy?.ping { success in
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

        let message = error?.localizedDescription ?? "无法注册后台帮助程序"
        return .registrationFailed(message)
    }

    private func setHelperExplicitlyDisabled(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: helperExplicitlyDisabledKey)
    }
}
