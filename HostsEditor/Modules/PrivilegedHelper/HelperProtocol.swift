//
//  HelperProtocol.swift
//  HostsEditor
//
//  与 HostsEditorHelper 中协议定义保持一致，用于 XPC 连接。
//

import Foundation

@objc public protocol HostsHelperProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func writeHosts(content: String, reply: @escaping (Bool, Error?) -> Void)
    func readHosts(reply: @escaping (String?, Error?) -> Void)
}
