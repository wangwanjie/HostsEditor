//
//  HelperDelegate.swift
//  HostsEditorHelper
//

import Foundation

private let hostsPath = "/etc/hosts"
/// 主应用的 bundle identifier，用于限制只有主应用可以连接 Helper
private let mainAppBundleIdentifier = "cn.vanjay.HostsEditor"
/// 单次写入的内容上限，防止异常数据把 /etc/hosts 写成超大文件
private let maximumHostsContentLength = 32 * 1024 * 1024

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HostsHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else {
            NSLog("Rejected helper connection from unauthorized client")
            return false
        }

        // 基于 audit token 的签名校验，避免仅凭 PID 校验时的 PID 复用竞态
        if let requirement = CodesignCheck.clientRequirement(forBundleIdentifier: mainAppBundleIdentifier) {
            newConnection.setCodeSigningRequirement(requirement)
        }

        newConnection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }

    private func isValidClient(connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.codeSigningMatches(pid: connection.processIdentifier)
        } catch {
            NSLog("Helper code signing check failed: %@", error.localizedDescription)
            return false
        }
    }
}

enum HostsHelperError: Error, LocalizedError {
    case contentTooLarge
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .contentTooLarge:
            return "Hosts content is too large."
        case .invalidContent:
            return "Hosts content contains invalid characters."
        }
    }
}

final class HostsHelperService: NSObject, HostsHelperProtocol {
    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func writeHosts(content: String, reply: @escaping (Bool, Error?) -> Void) {
        do {
            let data = Data(content.utf8)
            guard data.count <= maximumHostsContentLength else {
                throw HostsHelperError.contentTooLarge
            }
            // hosts 是纯文本文件，出现 NUL 字符说明数据异常，直接拒绝写入
            guard !data.contains(0) else {
                throw HostsHelperError.invalidContent
            }

            let url = URL(fileURLWithPath: hostsPath)
            try data.write(to: url, options: .atomic)
            // 原子写入会替换文件节点，这里显式恢复系统默认的属主和权限（root:wheel 0644）
            try FileManager.default.setAttributes(
                [
                    .posixPermissions: 0o644,
                    .ownerAccountID: 0,
                    .groupOwnerAccountID: 0,
                ],
                ofItemAtPath: hostsPath
            )
            flushDNSCache()
            reply(true, nil)
        } catch {
            reply(false, error)
        }
    }

    func readHosts(reply: @escaping (String?, Error?) -> Void) {
        do {
            let content = try String(contentsOfFile: hostsPath, encoding: .utf8)
            reply(content, nil)
        } catch {
            reply(nil, error)
        }
    }

    /// 刷新系统 DNS 缓存，让 hosts 修改立即生效；失败只记录日志，不影响写入结果
    private func flushDNSCache() {
        runTool("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        runTool("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
    }

    private func runTool(_ path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Failed to run %@: %@", path, error.localizedDescription)
        }
    }
}
