import Foundation
import GRDB

struct ProfileRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "profiles"

    var sortIndex: Int
    var id: String
    var name: String
    var content: String
    var isEnabled: Bool
    var isRemote: Bool
    var remoteURL: String?
    var lastUpdated: Date?

    enum CodingKeys: String, CodingKey {
        case sortIndex = "sort_index"
        case id
        case name
        case content
        case isEnabled
        case isRemote
        case remoteURL
        case lastUpdated
    }

    init(
        sortIndex: Int,
        id: String,
        name: String,
        content: String,
        isEnabled: Bool,
        isRemote: Bool,
        remoteURL: String?,
        lastUpdated: Date?
    ) {
        self.sortIndex = sortIndex
        self.id = id
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.isRemote = isRemote
        self.remoteURL = remoteURL
        self.lastUpdated = lastUpdated
    }

    init(profile: HostsProfile, sortIndex: Int) {
        self.sortIndex = sortIndex
        id = profile.id
        name = profile.name
        content = profile.content
        isEnabled = profile.isEnabled
        isRemote = profile.isRemote
        remoteURL = profile.remoteURL
        lastUpdated = profile.lastUpdated
    }

    var hostsProfile: HostsProfile {
        HostsProfile(
            id: id,
            name: name,
            content: content,
            isEnabled: isEnabled,
            isRemote: isRemote,
            remoteURL: remoteURL,
            lastUpdated: lastUpdated
        )
    }
}
