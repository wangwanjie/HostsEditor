//
//  PreferencesWindowController.swift
//  HostsEditor
//

import AppKit
import Combine
import SnapKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private static let autosaveName = NSWindow.FrameAutosaveName("HostsEditorPreferencesWindowFrame")

    private init() {
        let contentViewController = PreferencesViewController()
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 560, height: 320))
        window.minSize = NSSize(width: 560, height: 320)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class PreferencesViewController: NSViewController {
    private enum PreferencesSection: Int, CaseIterable {
        case updates
        case editor
        case helper

        var title: String {
            switch self {
            case .updates:
                return "更新"
            case .editor:
                return "编辑器"
            case .helper:
                return "帮助程序"
            }
        }
    }

    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentSection: PreferencesSection = .updates

    private var sectionControl: NSSegmentedControl!
    private var updatesSectionView: NSView!
    private var editorSectionView: NSView!
    private var helperSectionView: NSView!
    private var updateStrategyPopup: NSPopUpButton!
    private var automaticDownloadsCheckbox: NSButton!
    private var automaticDownloadsHintLabel: NSTextField!
    private var fontSizeSlider: NSSlider!
    private var fontSizeStepper: NSStepper!
    private var fontSizeValueLabel: NSTextField!
    private var helperStatusLabel: NSTextField!
    private var helperDetailLabel: NSTextField!
    private var disableHelperButton: NSButton!

    override func loadView() {
        view = NSView()
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindSettings()
        syncControlsFromSettings()
        syncHelperControls()
        syncVisibleSection()
    }

    private func buildUI() {
        sectionControl = NSSegmentedControl(
            labels: PreferencesSection.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(sectionChanged(_:))
        )
        sectionControl.selectedSegment = currentSection.rawValue

        updatesSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(title: "检查更新策略", control: makeUpdateStrategyControl()),
            automaticDownloadsCheckboxRow(),
            automaticDownloadsHint(),
            updatesActionRow(),
        ])

        editorSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(title: "Hosts 字体大小", control: makeFontSizeControl()),
        ])

        helperSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(title: "当前状态", control: makeHelperStatusView()),
            helperActionsRow(),
        ])

        let rootStack = NSStackView(views: [sectionControl, updatesSectionView, editorSectionView, helperSectionView])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        view.addSubview(rootStack)

        rootStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(22)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.lessThanOrEqualToSuperview().inset(22)
        }

        sectionControl.snp.makeConstraints { make in
            make.width.equalTo(rootStack)
        }

        updatesSectionView.snp.makeConstraints { make in
            make.width.equalTo(rootStack)
        }

        editorSectionView.snp.makeConstraints { make in
            make.width.equalTo(rootStack)
        }

        helperSectionView.snp.makeConstraints { make in
            make.width.equalTo(rootStack)
        }
    }

    private func bindSettings() {
        settings.$updateCheckStrategy
            .combineLatest(settings.$editorFontSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncControlsFromSettings()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncHelperControls()
            }
            .store(in: &cancellables)
    }

    private func syncControlsFromSettings() {
        if let index = UpdateCheckStrategy.allCases.firstIndex(of: settings.updateCheckStrategy) {
            updateStrategyPopup.selectItem(at: index)
        }

        let fontSize = settings.editorFontSize
        fontSizeSlider.doubleValue = fontSize
        fontSizeStepper.doubleValue = fontSize
        fontSizeValueLabel.stringValue = "\(Int(fontSize)) pt"

        automaticDownloadsCheckbox.state = UpdateManager.shared.automaticallyDownloadsUpdates ? .on : .off

        let automaticDownloadsAvailable = UpdateManager.shared.supportsAutomaticUpdateDownloads
        let strategyAllowsBackgroundUpdates = settings.updateCheckStrategy != .manual
        automaticDownloadsCheckbox.isEnabled = automaticDownloadsAvailable && strategyAllowsBackgroundUpdates

        if !automaticDownloadsAvailable {
            automaticDownloadsHintLabel.stringValue = "当前构建未启用 Sparkle 自动下载能力。"
        } else if strategyAllowsBackgroundUpdates {
            automaticDownloadsHintLabel.stringValue = "检测到新版本后可在后台自动下载，重启应用时安装。"
        } else {
            automaticDownloadsHintLabel.stringValue = "手动检查模式下不会在后台自动下载更新。"
        }
    }

    private func syncHelperControls() {
        let status = PrivilegedHostsWriter.shared.daemonStatus

        if HostsManager.shared.isHelperExplicitlyDisabled {
            helperStatusLabel.stringValue = "已停用"
            helperDetailLabel.stringValue = "后台帮助程序被手动停用。重新启用后才能继续写入系统 hosts。"
        } else {
            switch status {
            case .enabled:
                helperStatusLabel.stringValue = "已启用"
                helperDetailLabel.stringValue = "后台帮助程序可用。保持允许状态时，后续读写 hosts 不应再次请求授权。"
            case .requiresApproval:
                helperStatusLabel.stringValue = "等待系统允许"
                helperDetailLabel.stringValue = "请前往“系统设置 -> 通用 -> 登录项与扩展程序”允许 HostsEditor 的后台帮助程序。"
            case .notRegistered, .notFound:
                helperStatusLabel.stringValue = "未启用"
                helperDetailLabel.stringValue = "首次启用时会要求系统注册后台帮助程序；启用成功后才能写入 /etc/hosts。"
            @unknown default:
                helperStatusLabel.stringValue = "未知状态"
                helperDetailLabel.stringValue = "检测到未知的后台帮助程序状态，可尝试执行一次“启用或修复后台帮助程序”。"
            }
        }

        disableHelperButton.isEnabled = HostsManager.shared.hasRegisteredHelper
    }

    private func syncVisibleSection() {
        sectionControl.selectedSegment = currentSection.rawValue
        updatesSectionView.isHidden = currentSection != .updates
        editorSectionView.isHidden = currentSection != .editor
        helperSectionView.isHidden = currentSection != .helper
    }

    private func makeSectionCard(contentViews: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor

        let contentStack = NSStackView(views: contentViews)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        card.addSubview(contentStack)

        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(18)
        }

        return card
    }

    private func makeLabeledRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.alignment = .right
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.snp.makeConstraints { make in
            make.width.equalTo(112)
        }

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func makeUpdateStrategyControl() -> NSView {
        updateStrategyPopup = NSPopUpButton()
        updateStrategyPopup.addItems(withTitles: UpdateCheckStrategy.allCases.map(\.title))
        updateStrategyPopup.target = self
        updateStrategyPopup.action = #selector(updateStrategyChanged(_:))
        updateStrategyPopup.snp.makeConstraints { make in
            make.width.equalTo(200)
        }
        return updateStrategyPopup
    }

    private func automaticDownloadsCheckboxRow() -> NSView {
        automaticDownloadsCheckbox = NSButton(checkboxWithTitle: "自动下载更新", target: self, action: #selector(toggleAutomaticDownloads(_:)))
        automaticDownloadsCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize)
        return automaticDownloadsCheckbox
    }

    private func automaticDownloadsHint() -> NSView {
        automaticDownloadsHintLabel = NSTextField(wrappingLabelWithString: "")
        automaticDownloadsHintLabel.textColor = .secondaryLabelColor
        automaticDownloadsHintLabel.maximumNumberOfLines = 2
        automaticDownloadsHintLabel.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(440)
        }
        return automaticDownloadsHintLabel
    }

    private func updatesActionRow() -> NSView {
        let checkNowButton = NSButton(title: "立即检查更新", target: self, action: #selector(checkForUpdates))
        checkNowButton.bezelStyle = .rounded

        let resetButton = NSButton(title: "恢复默认设置", target: self, action: #selector(resetSettings))
        resetButton.bezelStyle = .rounded

        let row = NSStackView(views: [checkNowButton, resetButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeFontSizeControl() -> NSView {
        fontSizeSlider = NSSlider(
            value: AppSettings.defaultEditorFontSize,
            minValue: AppSettings.minEditorFontSize,
            maxValue: AppSettings.maxEditorFontSize,
            target: self,
            action: #selector(fontSizeSliderChanged(_:))
        )
        fontSizeSlider.isContinuous = true
        fontSizeSlider.snp.makeConstraints { make in
            make.width.equalTo(240)
        }

        fontSizeValueLabel = NSTextField(labelWithString: "")
        fontSizeValueLabel.alignment = .center
        fontSizeValueLabel.snp.makeConstraints { make in
            make.width.equalTo(50)
        }

        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = AppSettings.minEditorFontSize
        fontSizeStepper.maxValue = AppSettings.maxEditorFontSize
        fontSizeStepper.increment = 1
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged(_:))

        let row = NSStackView(views: [fontSizeSlider, fontSizeValueLabel, fontSizeStepper])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeHelperStatusView() -> NSView {
        helperStatusLabel = NSTextField(labelWithString: "")
        helperStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        helperDetailLabel = NSTextField(wrappingLabelWithString: "")
        helperDetailLabel.textColor = .secondaryLabelColor
        helperDetailLabel.maximumNumberOfLines = 3
        helperDetailLabel.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(440)
        }

        let stack = NSStackView(views: [helperStatusLabel, helperDetailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func helperActionsRow() -> NSView {
        let repairButton = NSButton(title: "启用或修复后台帮助程序", target: self, action: #selector(repairHelper))
        repairButton.bezelStyle = .rounded

        disableHelperButton = NSButton(title: "停用后台帮助程序", target: self, action: #selector(disableHelper))
        disableHelperButton.bezelStyle = .rounded

        let openSettingsButton = NSButton(title: "打开登录项设置", target: self, action: #selector(openHelperSettings))
        openSettingsButton.bezelStyle = .rounded

        let row = NSStackView(views: [repairButton, disableHelperButton, openSettingsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = PreferencesSection(rawValue: sender.selectedSegment) else { return }
        currentSection = section
        syncVisibleSection()
    }

    @objc private func updateStrategyChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard UpdateCheckStrategy.allCases.indices.contains(selectedIndex) else { return }
        settings.updateCheckStrategy = UpdateCheckStrategy.allCases[selectedIndex]
    }

    @objc private func toggleAutomaticDownloads(_ sender: NSButton) {
        UpdateManager.shared.automaticallyDownloadsUpdates = sender.state == .on
        syncControlsFromSettings()
    }

    @objc private func fontSizeSliderChanged(_ sender: NSSlider) {
        applyEditorFontSizeSelection(sender.doubleValue)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        applyEditorFontSizeSelection(sender.doubleValue)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func repairHelper() {
        Task { @MainActor in
            do {
                try await HostsManager.shared.reinstallHelper()
                syncHelperControls()
                presentInfoAlert(
                    title: "后台帮助程序已就绪",
                    message: "现在可以继续写入系统 hosts 文件。后续只要该后台帮助程序保持允许状态，就不需要再次授权。"
                )
            } catch let privilegedError as PrivilegedHostsError {
                handleHelperActionError(privilegedError)
            } catch {
                presentWarningAlert(title: "启用后台帮助程序失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func disableHelper() {
        let alert = NSAlert()
        alert.messageText = "停用后台帮助程序"
        alert.informativeText = "停用后将无法直接写入系统 hosts，直到重新启用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await HostsManager.shared.uninstallHelperAndWait()
                syncHelperControls()
                presentInfoAlert(title: "后台帮助程序已停用", message: "如需继续编辑系统 hosts，可在此页面重新启用。")
            } catch {
                presentWarningAlert(title: "停用后台帮助程序失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func openHelperSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func resetSettings() {
        settings.resetToDefaults()
        UpdateManager.shared.automaticallyDownloadsUpdates = false
        syncControlsFromSettings()
    }

    private func applyEditorFontSizeSelection(_ rawValue: Double) {
        let sanitized = AppSettings.clampedEditorFontSize(rawValue)
        fontSizeSlider.doubleValue = sanitized
        fontSizeStepper.doubleValue = sanitized
        fontSizeValueLabel.stringValue = "\(Int(sanitized)) pt"
        settings.editorFontSize = sanitized
    }

    private func handleHelperActionError(_ error: PrivilegedHostsError) {
        switch error {
        case .requiresApproval:
            let alert = NSAlert()
            alert.messageText = "需要允许后台帮助程序"
            alert.informativeText = "请前往“系统设置 -> 通用 -> 登录项与扩展程序”允许 HostsEditor 的后台帮助程序。开启后返回应用即可继续，无需再次授权。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .registrationFailed(let message):
            presentWarningAlert(title: "启用后台帮助程序失败", message: message)
        case .repairRequired(let message):
            presentWarningAlert(title: "后台帮助程序需要修复", message: message)
        default:
            presentWarningAlert(title: "启用后台帮助程序失败", message: error.localizedDescription)
        }
        syncHelperControls()
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    private func presentWarningAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
