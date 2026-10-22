//
//  DemoData.swift
//  HostsEditor
//
//  README 截图使用的演示数据：以 `--screenshot-demo` 启动时，应用使用内存数据和示例 hosts，
//  不读取也不修改真实的 /etc/hosts。
//

import Foundation
import ServiceManagement

/// 演示模式下的假 Helper，只在内存中保存 hosts 内容
final class DemoPrivilegedHostsWriter: PrivilegedHostsWriting {
    var daemonStatus: SMAppService.Status { .enabled }
    var isHelperInstalled: Bool { true }
    var isHelperExplicitlyDisabled: Bool { false }
    var hasRegisteredHelper: Bool { true }
    var hostsContent: String

    init(hostsContent: String) {
        self.hostsContent = hostsContent
    }

    func writeHosts(content: String) async throws {
        hostsContent = content
    }

    func enableHelper() async throws {}
    func uninstallHelperAndWait() async throws {}
    func reinstallHelper() async throws {}
}

enum DemoData {
    static let baseHosts = """
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1       localhost
    255.255.255.255 broadcasthost
    ::1             localhost
    """

    static let profiles: [HostsProfile] = [
        HostsProfile(
            id: "demo-dev",
            name: "开发环境",
            content: """
            # 本地开发服务
            127.0.0.1    api.example.dev
            127.0.0.1    web.example.dev
            127.0.0.1    admin.example.dev
            ::1          api.example.dev
            """,
            isEnabled: true
        ),
        HostsProfile(
            id: "demo-staging",
            name: "预发环境",
            content: """
            # 预发集群
            10.20.30.40  api.example.com
            10.20.30.41  web.example.com
            # 10.20.30.42  admin.example.com
            """
        ),
        HostsProfile(
            id: "demo-block",
            name: "屏蔽广告",
            content: """
            0.0.0.0  ads.example.net
            0.0.0.0  tracker.example.net
            """
        ),
        HostsProfile(
            id: "demo-remote",
            name: "☁️-team-shared",
            content: """
            # 团队共享配置
            192.168.1.10  git.team.internal
            192.168.1.11  ci.team.internal
            192.168.1.12  wiki.team.internal
            """,
            isEnabled: true,
            isRemote: true,
            remoteURL: "https://example.com/hosts/team-shared.hosts",
            lastUpdated: Date()
        ),
    ]

    /// 构造演示用的 HostsManager：内存数据库 + 内存 hosts
    @MainActor
    static func makeManager() -> HostsManager {
        let database: AppDatabase
        do {
            database = try AppDatabase.inMemory()
            try database.saveProfiles(profiles)
        } catch {
            fatalError("Failed to prepare demo database: \(error)")
        }
        let composed = HostsManager.composeHostsContent(base: baseHosts, profiles: profiles)
        let writer = DemoPrivilegedHostsWriter(hostsContent: composed)
        return HostsManager(
            database: database,
            privilegedWriter: writer,
            systemHostsReader: { writer.hostsContent },
            backupStore: nil
        )
    }
}
