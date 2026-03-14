//
//  HostsHelperProtocol.swift
//  HostsEditorHelper
//

import Foundation

@objc public protocol HostsHelperProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func writeHosts(content: String, reply: @escaping (Bool, Error?) -> Void)
    func readHosts(reply: @escaping (String?, Error?) -> Void)
}
