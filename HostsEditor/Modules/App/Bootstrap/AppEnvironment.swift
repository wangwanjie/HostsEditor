//
//  AppEnvironment.swift
//  HostsEditor
//

import Foundation

enum AppEnvironment {
    /// UI 测试启动应用时传入的参数
    static let uiTestingArgument = "--uitesting"
    /// README 截图使用的演示模式参数
    static let screenshotDemoArgument = "--screenshot-demo"

    static var isScreenshotDemo: Bool {
        ProcessInfo.processInfo.arguments.contains(screenshotDemoArgument)
    }

    /// 当前进程是否作为单元测试宿主、UI 测试目标或截图演示运行；这些场景都不触碰用户真实数据
    static var isRunningTests: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return processInfo.arguments.contains(uiTestingArgument) || isScreenshotDemo
    }
}
