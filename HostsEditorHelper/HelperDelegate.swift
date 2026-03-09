//
//  HelperDelegate.swift
//  HostsEditorHelper
//

import Foundation

private let hostsPath = "/etc/hosts"

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        newConnection.exportedObject = HostsHelperService()
        newConnection.resume()
        return true
    }
}

final class HostsHelperService: NSObject, HostsHelperProtocol {
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
