//
//  main.swift
//  HostsEditorHelper
//
//  Privileged helper tool: receives hosts content via XPC and writes to /etc/hosts.
//

import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
exit(0)
