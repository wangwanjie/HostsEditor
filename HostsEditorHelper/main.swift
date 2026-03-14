//
//  main.swift
//  HostsEditorHelper
//
//  Privileged helper tool: receives hosts content via XPC and writes to /etc/hosts.
//

import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "cn.vanjay.HostsEditorHelper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
