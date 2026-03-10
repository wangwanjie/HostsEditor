//
//  PrivilegedHostsWriter.swift
//  HostsEditor
//
//  通过 SMAppService 注册 Helper Daemon，通过 XPC 写入 /etc/hosts。
//

import Foundation
import ServiceManagement

private let helperLabel = "cn.vanjay.HostsEditor.Helper"
private let daemonPlistName = "cn.vanjay.HostsEditor.Helper.plist"

enum PrivilegedHostsError: Error, LocalizedError {
    case requiresApproval
    case connectionFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "需要在「系统设置 → 通用 → 登录项与扩展程序」中允许后台程序"
        case .connectionFailed:
            return "无法连接帮助程序"
        case .timeout:
            return "连接超时"
        }
    }
}

final class PrivilegedHostsWriter {

    static let shared = PrivilegedHostsWriter()
    private init() {}

    // MARK: - 状态

    var daemonStatus: SMAppService.Status {
        SMAppService.daemon(plistName: daemonPlistName).status
    }

    var isHelperInstalled: Bool {
        daemonStatus == .enabled
    }

    // MARK: - 安装

    /// 注册 Daemon。
    /// - 返回 nil：已启用，无需任何操作。
    /// - 返回 PrivilegedHostsError.requiresApproval：需要用户在系统设置中手动允许。
    /// - 返回其他 Error：注册失败。
    func installHelperIfNeeded() -> Error? {
        let service = SMAppService.daemon(plistName: daemonPlistName)

        switch service.status {
        case .enabled:
            return nil
        case .requiresApproval:
            return PrivilegedHostsError.requiresApproval
        default:
            break
        }

        do {
            try service.register()
            if service.status == .requiresApproval {
                return PrivilegedHostsError.requiresApproval
            }
            return nil
        } catch {
            return error
        }
    }

    // MARK: - XPC 操作

    /// 将内容写入系统 hosts 文件
    func writeHosts(content: String) async throws {
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] err in
                conn?.invalidate()
                cont.resume(throwing: err)
            } as! HostsHelperProtocol
            proxy.writeHosts(content: content) { success, error in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? PrivilegedHostsError.connectionFailed)
                }
            }
        }
    }

    /// 从系统读取当前 hosts 内容（带 5 秒超时）
    func readHosts() async throws -> String {
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var finished = false
            let lock = NSLock()
            func resumeOnce(_ result: Result<String, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                switch result {
                case .success(let s): cont.resume(returning: s)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                resumeOnce(.failure(PrivilegedHostsError.timeout))
            }
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] err in
                conn?.invalidate()
                resumeOnce(.failure(err))
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
}
