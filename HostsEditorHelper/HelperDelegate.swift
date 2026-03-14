//
//  HelperDelegate.swift
//  HostsEditorHelper
//

import Foundation

private let hostsPath = "/etc/hosts"

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HostsHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else {
            NSLog("Rejected helper connection from unauthorized client")
            return false
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

final class HostsHelperService: NSObject, HostsHelperProtocol {
    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func writeHosts(content: String, reply: @escaping (Bool, Error?) -> Void) {
        do {
            let data = Data(content.utf8)
            try data.write(to: URL(fileURLWithPath: hostsPath), options: .atomic)
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
}
