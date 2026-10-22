//
//  HostsEditorUITests.swift
//  HostsEditorUITests
//
//  Created by VanJay on 2026/3/9.
//

import XCTest

final class HostsEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 以测试模式启动：跳过 Helper 安装弹窗、自动更新检查，并使用内存数据库
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
        return app
    }

    @MainActor
    func testMainWindowShowsSidebarAndEditor() throws {
        let app = launchApp()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.tables["Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.textViews.firstMatch.exists)
    }

    @MainActor
    func testFileMenuProvidesProfileActions() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems.element(boundBy: 1)
        fileMenu.click()

        // 文件菜单中的条目都应可用（不再有无动作的占位项）
        let items = fileMenu.menus.firstMatch.menuItems
        XCTAssertGreaterThanOrEqual(items.count, 5)
        app.typeKey(.escape, modifierFlags: [])
    }
}
