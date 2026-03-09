//
//  PrivilegedHostsWriter.swift
//  HostsEditor
//
//  通过 SMJobBless 安装的 Helper 与 XPC 写入 /etc/hosts。
//

import Foundation
import ServiceManagement
import Security

private let helperLabel = "cn.vanjay.HostsEditor.Helper"

enum PrivilegedHostsError: Error {
    case blessFailed(String)
    case connectionFailed
    case helperNotInstalled
    case timeout
}

final class PrivilegedHostsWriter {

    static let shared = PrivilegedHostsWriter()

    private var connection: NSXPCConnection?

    private init() {}

    /// 检查 Helper 是否已安装并可连接
    var isHelperInstalled: Bool {
        let conn = makeConnection()
        defer { conn?.invalidate() }
        return conn != nil
    }

    /// 安装 Helper（首次或更新后需管理员授权）
    func installHelperIfNeeded() -> Error? {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            return PrivilegedHostsError.blessFailed("无法创建授权引用")
        }
        defer { AuthorizationFree(auth, []); if authRef != nil {} }

        var error: Unmanaged<CFError>?
        let blessed = SMJobBless(kSMDomainSystemLaunchd, helperLabel as CFString, auth, &error)
        if !blessed {
            let err = error?.takeRetainedValue()
            return PrivilegedHostsError.blessFailed((err as Error?)?.localizedDescription ?? "未知错误")
        }
        return nil
    }

    /// 将内容写入系统 hosts 文件
    func writeHosts(content: String) async throws {
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] err in
                conn?.invalidate()
                continuation.resume(throwing: err)
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

    /// 从系统读取当前 hosts 内容（带超时，避免 Helper 未响应时界面一直不更新）
    func readHosts() async throws -> String {
        guard let conn = makeConnection() else {
            throw PrivilegedHostsError.connectionFailed
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var finished = false
            let lock = NSLock()
            func resumeOnce(result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                switch result {
                case .success(let s): continuation.resume(returning: s)
                case .failure(let e): continuation.resume(throwing: e)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                resumeOnce(result: .failure(PrivilegedHostsError.timeout))
            }
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak conn] err in
                conn?.invalidate()
                resumeOnce(result: .failure(err))
            } as! HostsHelperProtocol
            proxy.readHosts { content, error in
                if let content = content {
                    resumeOnce(result: .success(content))
                } else {
                    resumeOnce(result: .failure(error ?? PrivilegedHostsError.connectionFailed))
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
