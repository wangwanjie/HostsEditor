//
//  RemoteProfileAutoRefresher.swift
//  HostsEditor
//
//  按偏好设置中的间隔，定期刷新过期的远程方案。
//

import Foundation
import Combine

@MainActor
final class RemoteProfileAutoRefresher {
    /// 检查是否有过期方案的轮询周期；真正的刷新间隔由设置决定
    nonisolated static let defaultCheckInterval: TimeInterval = 5 * 60

    private let manager: HostsManager
    private let settings: AppSettings
    private let checkInterval: TimeInterval
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isRefreshing = false

    init(manager: HostsManager, settings: AppSettings, checkInterval: TimeInterval = RemoteProfileAutoRefresher.defaultCheckInterval) {
        self.manager = manager
        self.settings = settings
        self.checkInterval = checkInterval
    }

    func start() {
        guard cancellables.isEmpty else {
            return
        }
        settings.$remoteRefreshInterval
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] interval in
                self?.reschedule(for: interval)
            }
            .store(in: &cancellables)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    var isScheduled: Bool {
        timer != nil
    }

    /// 立即检查一次，供定时器和测试调用；返回本次尝试刷新的方案数量
    @discardableResult
    func refreshIfNeeded(now: Date = Date()) async -> Int {
        guard let interval = settings.remoteRefreshInterval.seconds, !isRefreshing else {
            return 0
        }
        isRefreshing = true
        defer { isRefreshing = false }
        return await manager.refreshStaleRemoteProfiles(olderThan: interval, now: now)
    }

    private func reschedule(for interval: RemoteRefreshInterval) {
        timer?.invalidate()
        timer = nil
        guard interval.seconds != nil else {
            return
        }

        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshIfNeeded()
            }
        }
        timer.tolerance = checkInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 开启或切换间隔后立即检查一次，不必等第一个轮询周期
        Task { @MainActor [weak self] in
            await self?.refreshIfNeeded()
        }
    }
}
