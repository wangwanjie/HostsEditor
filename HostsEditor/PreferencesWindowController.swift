//
//  PreferencesWindowController.swift
//  HostsEditor
//

import AppKit
import Combine
import ServiceManagement
import SnapKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController(updateManager: .shared, settings: .shared)

    private static let autosaveName = NSWindow.FrameAutosaveName("HostsEditorPreferencesWindowFrame")

    private var cancellables = Set<AnyCancellable>()

    init(updateManager: UpdateManager, settings: AppSettings? = nil) {
        let resolvedSettings = settings ?? .shared
        let contentViewController = PreferencesViewController(updateManager: updateManager, settings: resolvedSettings)
        let window = NSWindow(contentViewController: contentViewController)
        window.title = L10n.preferencesWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 620, height: 360))
        window.minSize = NSSize(width: 620, height: 360)
        super.init(window: window)
        shouldCascadeWindows = false

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        bindLocalization()
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

    private func bindLocalization() {
        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.window?.title = L10n.preferencesWindowTitle
            }
            .store(in: &cancellables)
    }

    var debugLanguagePopup: NSPopUpButton {
        preferencesViewController.debugLanguagePopup
    }

    var debugAppearancePopup: NSPopUpButton {
        preferencesViewController.debugAppearancePopup
    }

    var debugSectionLabels: [String] {
        preferencesViewController.debugSectionLabels
    }

    var debugEffectiveAppearance: NSAppearance {
        preferencesViewController.view.effectiveAppearance
    }

    private var preferencesViewController: PreferencesViewController {
        window?.contentViewController as! PreferencesViewController
    }
}

@MainActor
private final class PreferencesViewController: NSViewController {
    private enum PreferencesSection: Int, CaseIterable {
        case general
        case updates
        case editor
        case helper

        var title: String {
            switch self {
            case .general:
                return L10n.preferencesSectionGeneral
            case .updates:
                return L10n.preferencesSectionUpdates
            case .editor:
                return L10n.preferencesSectionEditor
            case .helper:
                return L10n.preferencesSectionHelper
            }
        }
    }

    private let updateManager: UpdateManager
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var currentSection: PreferencesSection = .general

    private let sectionControl = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .selectOne, target: nil, action: nil)

    private var generalSectionView: NSView!
    private var updatesSectionView: NSView!
    private var editorSectionView: NSView!
    private var helperSectionView: NSView!
    private var cardViews: [NSView] = []

    private var languagePopup: NSPopUpButton!
    private var appearancePopup: NSPopUpButton!
    private var updateStrategyPopup: NSPopUpButton!
    private var automaticDownloadsCheckbox: NSButton!
    private var automaticDownloadsHintLabel: NSTextField!
    private var fontSizeSlider: NSSlider!
    private var fontSizeStepper: NSStepper!
    private var fontSizeValueLabel: NSTextField!
    private var helperStatusLabel: NSTextField!
    private var helperDetailLabel: NSTextField!
    private var disableHelperButton: NSButton!

    private var checkNowButton: NSButton!
    private var resetButton: NSButton!
    private var repairButton: NSButton!
    private var openSettingsButton: NSButton!

    private var generalLanguageLabel: NSTextField!
    private var generalAppearanceLabel: NSTextField!
    private var updatesStrategyLabel: NSTextField!
    private var editorFontSizeLabel: NSTextField!
    private var helperStatusTitleLabel: NSTextField!

    init(updateManager: UpdateManager, settings: AppSettings) {
        self.updateManager = updateManager
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let appearanceAwareView = AppearanceAwareView()
        appearanceAwareView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearanceColors()
        }
        view = appearanceAwareView
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindSettings()
        applyLocalization()
        syncControlsFromSettings()
        syncHelperControls()
        syncVisibleSection()
        updateAppearanceColors()
    }

    private func buildUI() {
        sectionControl.segmentStyle = .rounded
        sectionControl.selectedSegment = currentSection.rawValue
        sectionControl.target = self
        sectionControl.action = #selector(sectionChanged(_:))

        generalSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(labelStorage: &generalLanguageLabel, title: L10n.preferencesLanguage, control: makeLanguagePopup()),
            makeLabeledRow(labelStorage: &generalAppearanceLabel, title: L10n.preferencesAppearance, control: makeAppearancePopup()),
        ])

        updatesSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(labelStorage: &updatesStrategyLabel, title: L10n.preferencesUpdateCheckStrategy, control: makeUpdateStrategyControl()),
            automaticDownloadsCheckboxRow(),
            automaticDownloadsHint(),
            updatesActionRow(),
        ])

        editorSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(labelStorage: &editorFontSizeLabel, title: L10n.preferencesEditorFontSize, control: makeFontSizeControl()),
        ])

        helperSectionView = makeSectionCard(contentViews: [
            makeLabeledRow(labelStorage: &helperStatusTitleLabel, title: L10n.preferencesCurrentStatus, control: makeHelperStatusView()),
            helperActionsRow(),
        ])

        let rootStack = NSStackView(views: [sectionControl, generalSectionView, updatesSectionView, editorSectionView, helperSectionView])
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

        for sectionView in [generalSectionView, updatesSectionView, editorSectionView, helperSectionView] {
            sectionView?.snp.makeConstraints { make in
                make.width.equalTo(rootStack)
            }
        }
    }

    private func bindSettings() {
        settings.$appLanguage
            .combineLatest(settings.$appAppearance, settings.$updateCheckStrategy, settings.$editorFontSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.syncControlsFromSettings()
            }
            .store(in: &cancellables)

        AppLocalization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLocalization()
                self?.syncControlsFromSettings()
                self?.syncHelperControls()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncHelperControls()
            }
            .store(in: &cancellables)
    }

    private func applyLocalization() {
        sectionControl.segmentCount = PreferencesSection.allCases.count
        for section in PreferencesSection.allCases {
            sectionControl.setLabel(section.title, forSegment: section.rawValue)
        }
        updateSectionControlWidths()

        generalLanguageLabel.stringValue = L10n.preferencesLanguage
        generalAppearanceLabel.stringValue = L10n.preferencesAppearance
        updatesStrategyLabel.stringValue = L10n.preferencesUpdateCheckStrategy
        editorFontSizeLabel.stringValue = L10n.preferencesEditorFontSize
        helperStatusTitleLabel.stringValue = L10n.preferencesCurrentStatus

        automaticDownloadsCheckbox.title = L10n.preferencesAutoDownloads
        checkNowButton.title = L10n.preferencesCheckForUpdatesNow
        resetButton.title = L10n.preferencesResetDefaults
        repairButton.title = L10n.preferencesRepairHelper
        disableHelperButton.title = L10n.preferencesDisableHelper
        openSettingsButton.title = L10n.preferencesOpenLoginItems

        rebuildLanguagePopup()
        rebuildAppearancePopup()
        rebuildUpdateStrategyPopup()
    }

    private func updateSectionControlWidths() {
        let font = sectionControl.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let horizontalPadding: CGFloat = 28
        let minimumSegmentWidth: CGFloat = 72

        for section in PreferencesSection.allCases {
            let title = section.title as NSString
            let textWidth = ceil(title.size(withAttributes: [.font: font]).width)
            let segmentWidth = max(minimumSegmentWidth, textWidth + horizontalPadding)
            sectionControl.setWidth(segmentWidth, forSegment: section.rawValue)
        }

        sectionControl.needsLayout = true
    }

    private func syncControlsFromSettings() {
        if let languageIndex = AppLanguage.allCases.firstIndex(of: settings.appLanguage) {
            languagePopup.selectItem(at: languageIndex)
        }
        if let appearanceIndex = AppAppearance.allCases.firstIndex(of: settings.appAppearance) {
            appearancePopup.selectItem(at: appearanceIndex)
        }
        if let strategyIndex = UpdateCheckStrategy.allCases.firstIndex(of: settings.updateCheckStrategy) {
            updateStrategyPopup.selectItem(at: strategyIndex)
        }

        let fontSize = settings.editorFontSize
        fontSizeSlider.doubleValue = fontSize
        fontSizeStepper.doubleValue = fontSize
        fontSizeValueLabel.stringValue = "\(Int(fontSize)) pt"

        automaticDownloadsCheckbox.state = updateManager.automaticallyDownloadsUpdates ? .on : .off

        let automaticDownloadsAvailable = updateManager.supportsAutomaticUpdateDownloads
        let strategyAllowsBackgroundUpdates = settings.updateCheckStrategy != .manual
        automaticDownloadsCheckbox.isEnabled = automaticDownloadsAvailable && strategyAllowsBackgroundUpdates

        if !automaticDownloadsAvailable {
            automaticDownloadsHintLabel.stringValue = L10n.preferencesAutoDownloadsUnavailable
        } else if strategyAllowsBackgroundUpdates {
            automaticDownloadsHintLabel.stringValue = L10n.preferencesAutoDownloadsAvailable
        } else {
            automaticDownloadsHintLabel.stringValue = L10n.preferencesAutoDownloadsManual
        }
    }

    private func syncHelperControls() {
        let status = PrivilegedHostsWriter.shared.daemonStatus

        if HostsManager.shared.isHelperExplicitlyDisabled {
            helperStatusLabel.stringValue = L10n.helperStatusDisabled
            helperDetailLabel.stringValue = L10n.helperDetailDisabled
        } else {
            switch status {
            case .enabled:
                helperStatusLabel.stringValue = L10n.helperStatusEnabled
                helperDetailLabel.stringValue = L10n.helperDetailEnabled
            case .requiresApproval:
                helperStatusLabel.stringValue = L10n.helperStatusPending
                helperDetailLabel.stringValue = L10n.helperDetailPending
            case .notRegistered, .notFound:
                helperStatusLabel.stringValue = L10n.helperStatusNotEnabled
                helperDetailLabel.stringValue = L10n.helperDetailNotEnabled
            @unknown default:
                helperStatusLabel.stringValue = L10n.helperStatusUnknown
                helperDetailLabel.stringValue = L10n.helperDetailUnknown
            }
        }

        disableHelperButton.isEnabled = HostsManager.shared.hasRegisteredHelper
    }

    private func syncVisibleSection() {
        sectionControl.selectedSegment = currentSection.rawValue
        generalSectionView.isHidden = currentSection != .general
        updatesSectionView.isHidden = currentSection != .updates
        editorSectionView.isHidden = currentSection != .editor
        helperSectionView.isHidden = currentSection != .helper
    }

    private func updateAppearanceColors() {
        for card in cardViews {
            card.layer?.backgroundColor = resolvedCGColor(NSColor.controlBackgroundColor, appearance: view.effectiveAppearance)
            card.layer?.borderColor = resolvedCGColor(NSColor.separatorColor, appearance: view.effectiveAppearance)
        }
    }

    private func makeSectionCard(contentViews: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        cardViews.append(card)

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

    private func makeLabeledRow(labelStorage: inout NSTextField!, title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.alignment = .right
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.snp.makeConstraints { make in
            make.width.equalTo(112)
        }
        labelStorage = titleLabel

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func makeLanguagePopup() -> NSView {
        languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        languagePopup.snp.makeConstraints { make in
            make.width.equalTo(200)
        }
        return languagePopup
    }

    private func makeAppearancePopup() -> NSView {
        appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged(_:))
        appearancePopup.snp.makeConstraints { make in
            make.width.equalTo(200)
        }
        return appearancePopup
    }

    private func makeUpdateStrategyControl() -> NSView {
        updateStrategyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        updateStrategyPopup.target = self
        updateStrategyPopup.action = #selector(updateStrategyChanged(_:))
        updateStrategyPopup.snp.makeConstraints { make in
            make.width.equalTo(200)
        }
        return updateStrategyPopup
    }

    private func automaticDownloadsCheckboxRow() -> NSView {
        automaticDownloadsCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleAutomaticDownloads(_:)))
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
        checkNowButton = NSButton(title: "", target: self, action: #selector(checkForUpdates))
        checkNowButton.bezelStyle = .rounded

        resetButton = NSButton(title: "", target: self, action: #selector(resetSettings))
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
        repairButton = NSButton(title: "", target: self, action: #selector(repairHelper))
        repairButton.bezelStyle = .rounded

        disableHelperButton = NSButton(title: "", target: self, action: #selector(disableHelper))
        disableHelperButton.bezelStyle = .rounded

        openSettingsButton = NSButton(title: "", target: self, action: #selector(openHelperSettings))
        openSettingsButton.bezelStyle = .rounded

        let row = NSStackView(views: [repairButton, disableHelperButton, openSettingsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func rebuildLanguagePopup() {
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(L10n.languageName))
    }

    private func rebuildAppearancePopup() {
        appearancePopup.removeAllItems()
        appearancePopup.addItems(withTitles: AppAppearance.allCases.map(L10n.appearanceName))
    }

    private func rebuildUpdateStrategyPopup() {
        updateStrategyPopup.removeAllItems()
        updateStrategyPopup.addItems(withTitles: UpdateCheckStrategy.allCases.map(\.title))
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = PreferencesSection(rawValue: sender.selectedSegment) else { return }
        currentSection = section
        syncVisibleSection()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(selectedIndex) else { return }
        settings.appLanguage = AppLanguage.allCases[selectedIndex]
    }

    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard AppAppearance.allCases.indices.contains(selectedIndex) else { return }
        settings.appAppearance = AppAppearance.allCases[selectedIndex]
    }

    @objc private func updateStrategyChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard UpdateCheckStrategy.allCases.indices.contains(selectedIndex) else { return }
        settings.updateCheckStrategy = UpdateCheckStrategy.allCases[selectedIndex]
    }

    @objc private func toggleAutomaticDownloads(_ sender: NSButton) {
        updateManager.automaticallyDownloadsUpdates = sender.state == .on
        syncControlsFromSettings()
    }

    @objc private func fontSizeSliderChanged(_ sender: NSSlider) {
        applyEditorFontSizeSelection(sender.doubleValue)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        applyEditorFontSizeSelection(sender.doubleValue)
    }

    @objc private func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    @objc private func repairHelper() {
        Task { @MainActor in
            do {
                try await HostsManager.shared.reinstallHelper()
                syncHelperControls()
                presentInfoAlert(
                    title: L10n.tr("helper.alert.ready.title"),
                    message: L10n.tr("helper.alert.ready.message")
                )
            } catch let privilegedError as PrivilegedHostsError {
                handleHelperActionError(privilegedError)
            } catch {
                presentWarningAlert(title: L10n.tr("helper.alert.enable_failed.title"), message: error.localizedDescription)
            }
        }
    }

    @objc private func disableHelper() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.disable.title")
        alert.informativeText = L10n.tr("helper.alert.disable.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.disable"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await HostsManager.shared.uninstallHelperAndWait()
                syncHelperControls()
                presentInfoAlert(title: L10n.tr("helper.alert.disabled_done.title"), message: L10n.tr("helper.alert.disabled_done.message"))
            } catch {
                presentWarningAlert(title: L10n.preferencesDisableHelper, message: error.localizedDescription)
            }
        }
    }

    @objc private func openHelperSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func resetSettings() {
        settings.resetToDefaults()
        updateManager.automaticallyDownloadsUpdates = false
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
            alert.messageText = L10n.tr("helper.alert.approval.title")
            alert.informativeText = L10n.tr("helper.alert.approval.message")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.tr("common.open_system_settings"))
            alert.addButton(withTitle: L10n.tr("common.cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .registrationFailed(let message):
            presentWarningAlert(title: L10n.tr("helper.alert.enable_failed.title"), message: message)
        case .repairRequired(let message):
            presentWarningAlert(title: L10n.tr("helper.alert.repair_required.title"), message: message)
        default:
            presentWarningAlert(title: L10n.tr("helper.alert.enable_failed.title"), message: error.localizedDescription)
        }
        syncHelperControls()
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    private func presentWarningAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    var debugLanguagePopup: NSPopUpButton {
        languagePopup
    }

    var debugAppearancePopup: NSPopUpButton {
        appearancePopup
    }

    var debugSectionLabels: [String] {
        (0..<sectionControl.segmentCount).map { sectionControl.label(forSegment: $0) ?? "" }
    }
}

private func resolvedCGColor(_ color: NSColor, appearance: NSAppearance) -> CGColor {
    let previousAppearance = NSAppearance.current
    NSAppearance.current = appearance
    let resolvedColor = color.usingColorSpace(.deviceRGB)?.cgColor ?? color.cgColor
    NSAppearance.current = previousAppearance
    return resolvedColor
}

private final class AppearanceAwareView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onEffectiveAppearanceChange?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
