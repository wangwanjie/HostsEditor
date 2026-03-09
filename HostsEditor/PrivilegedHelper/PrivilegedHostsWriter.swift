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
private let helperInstallPath = "/Library/PrivilegedHelperTools/cn.vanjay.HostsEditor.Helper"

enum PrivilegedHostsError: Error, LocalizedError {
    case blessFailed(String)
    case connectionFailed
    case helperNotInstalled
    case timeout

    var errorDescription: String? {
        switch self {
        case .blessFailed(let msg): return msg.isEmpty ? "安装失败（多为签名/Team ID 不匹配）" : msg
        case .connectionFailed: return "无法连接帮助程序"
        case .helperNotInstalled: return "帮助程序未安装"
        case .timeout: return "连接超时"
        }
    }
}

final class PrivilegedHostsWriter {

    static let shared = PrivilegedHostsWriter()

    private var connection: NSXPCConnection?

    private init() {}

    /// 检查 Helper 是否已安装（仅看 SMJobBless 是否已把可执行文件拷到系统目录，不依赖 XPC 连接）
    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: helperInstallPath)
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
            var msg: String
            if let cfErr = err {
                let desc = CFErrorCopyDescription(cfErr) as String? ?? ""
                msg = desc.isEmpty ? "SMJobBless 失败（常见原因：签名不匹配，请确认主应用与 Helper 用同一 Team 签名）" : desc
            } else {
                msg = "未知错误"
            }
            return PrivilegedHostsError.blessFailed(msg)
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
