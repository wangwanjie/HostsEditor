//
//  HostsProfile.swift
//  HostsEditor
//

import Foundation

struct HostsProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var content: String
    var isEnabled: Bool
    var isRemote: Bool
    var remoteURL: String?
    var lastUpdated: Date?

    init(id: String = UUID().uuidString,
         name: String,
         content: String = "",
         isEnabled: Bool = false,
         isRemote: Bool = false,
         remoteURL: String? = nil,
         lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.isRemote = isRemote
        self.remoteURL = remoteURL
        self.lastUpdated = lastUpdated
    }
}
