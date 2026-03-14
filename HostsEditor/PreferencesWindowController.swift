//
//  PreferencesWindowController.swift
//  HostsEditor
//

import AppKit
import Combine
import SnapKit

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

        var title: String {
            switch self {
            case .updates:
                return "更新"
            case .editor:
                return "编辑器"
            }
        }
    }

    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentSection: PreferencesSection = .updates

    private var sectionControl: NSSegmentedControl!
    private var updatesSectionView: NSView!
    private var editorSectionView: NSView!
    private var updateStrategyPopup: NSPopUpButton!
    private var automaticDownloadsCheckbox: NSButton!
    private var automaticDownloadsHintLabel: NSTextField!
    private var fontSizeSlider: NSSlider!
    private var fontSizeStepper: NSStepper!
    private var fontSizeValueLabel: NSTextField!

    override func loadView() {
        view = NSView()
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindSettings()
        syncControlsFromSettings()
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

        let rootStack = NSStackView(views: [sectionControl, updatesSectionView, editorSectionView])
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
    }

    private func bindSettings() {
        settings.$updateCheckStrategy
            .combineLatest(settings.$editorFontSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncControlsFromSettings()
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

    private func syncVisibleSection() {
        sectionControl.selectedSegment = currentSection.rawValue
        updatesSectionView.isHidden = currentSection != .updates
        editorSectionView.isHidden = currentSection != .editor
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
        settings.editorFontSize = sender.doubleValue
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        settings.editorFontSize = sender.doubleValue
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func resetSettings() {
        settings.resetToDefaults()
        UpdateManager.shared.automaticallyDownloadsUpdates = false
        syncControlsFromSettings()
    }
}
