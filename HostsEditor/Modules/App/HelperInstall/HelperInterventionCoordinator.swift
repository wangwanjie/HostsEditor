import Cocoa
import ServiceManagement

@MainActor
final class HelperInterventionCoordinator: NSObject {
    private let manager: HostsManager
    private let privilegedWriter: PrivilegedHostsWriter
    private let notificationCenter: NotificationCenter
    private let activateApp: () -> Void
    private let openSystemSettingsLoginItems: () -> Void

    private var isObserving = false
    private var isPresentingHelperInterventionAlert = false
    private var shouldRetryPendingOperationAfterActivation = false

    init(
        manager: HostsManager? = nil,
        privilegedWriter: PrivilegedHostsWriter? = nil,
        notificationCenter: NotificationCenter = .default,
        activateApp: (() -> Void)? = nil,
        openSystemSettingsLoginItems: (() -> Void)? = nil
    ) {
        self.manager = manager ?? .shared
        self.privilegedWriter = privilegedWriter ?? .shared
        self.notificationCenter = notificationCenter
        self.activateApp = activateApp ?? { NSApp.activate(ignoringOtherApps: true) }
        self.openSystemSettingsLoginItems = openSystemSettingsLoginItems ?? { SMAppService.openSystemSettingsLoginItems() }
        super.init()
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        notificationCenter.addObserver(
            self,
            selector: #selector(handleHelperInterventionNotification(_:)),
            name: .hostsEditorHelperInterventionRequired,
            object: nil
        )
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        notificationCenter.removeObserver(self)
    }

    func applicationDidBecomeActive() {
        guard shouldRetryPendingOperationAfterActivation else { return }

        switch privilegedWriter.daemonStatus {
        case .enabled:
            shouldRetryPendingOperationAfterActivation = false
            Task { @MainActor in
                await manager.retryPendingPrivilegedOperationIfNeeded()
            }
        case .requiresApproval:
            return
        case .notRegistered, .notFound:
            shouldRetryPendingOperationAfterActivation = false
        @unknown default:
            shouldRetryPendingOperationAfterActivation = false
        }
    }

    func promptForHelperIfNeeded() {
        if manager.isHelperExplicitlyDisabled {
            return
        }

        switch privilegedWriter.daemonStatus {
        case .enabled:
            return
        case .notRegistered, .notFound:
            presentHelperInstallAlert(operation: nil)
        case .requiresApproval:
            presentHelperApprovalAlert(operation: nil)
        @unknown default:
            return
        }
    }

    func installHelperFromMenu() {
        performHelperSetup(forceRepair: true, announceSuccess: true)
    }

    func uninstallHelperFromMenu() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.disable.title")
        alert.informativeText = L10n.tr("helper.alert.disable.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.disable"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await manager.uninstallHelperAndWait()
                let success = NSAlert()
                success.messageText = L10n.tr("helper.alert.disabled_done.title")
                success.informativeText = L10n.tr("helper.alert.disabled_done.message")
                success.alertStyle = .informational
                success.addButton(withTitle: L10n.tr("common.ok"))
                success.runModal()
            } catch {
                let failure = NSAlert()
                failure.messageText = L10n.tr("helper.alert.disable_failed.title")
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: L10n.tr("common.ok"))
                failure.runModal()
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(AppDelegate.installHelperFromMenu):
            return true
        case #selector(AppDelegate.uninstallHelperFromMenu):
            return manager.hasRegisteredHelper
        default:
            return true
        }
    }

    private func presentHelperInstallAlert(operation: String?) {
        activateApp()

        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.install.title")
        if let operation {
            alert.informativeText = L10n.tr("helper.alert.install.operation_message", operation)
        } else {
            alert.informativeText = L10n.tr("helper.alert.install.message")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.enable_now"))
        alert.addButton(withTitle: L10n.tr("common.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            performHelperSetup(
                forceRepair: false,
                announceSuccess: false,
                retryPendingOperation: operation != nil
            )
        }
    }

    private func presentHelperApprovalAlert(operation: String?) {
        activateApp()

        let alert = NSAlert()
        alert.messageText = L10n.tr("helper.alert.approval.title")
        if let operation {
            alert.informativeText = L10n.tr("helper.alert.approval.operation_message", operation)
        } else {
            alert.informativeText = L10n.tr("helper.alert.approval.message")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.open_system_settings"))
        alert.addButton(withTitle: L10n.tr("common.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            shouldRetryPendingOperationAfterActivation = operation != nil
            openSystemSettingsLoginItems()
        }
    }

    private func showHelperInstallError(_ error: Error) {
        let alert = NSAlert()
        if let privilegedError = error as? PrivilegedHostsError {
            switch privilegedError {
            case .registrationFailed(let message):
                alert.messageText = L10n.tr("helper.alert.enable_failed.title")
                alert.informativeText = message
            case .repairRequired(let message):
                alert.messageText = L10n.tr("helper.alert.repair_required.title")
                alert.informativeText = message
            default:
                alert.messageText = L10n.tr("helper.alert.enable_failed.title")
                alert.informativeText = error.localizedDescription
            }
        } else {
            alert.messageText = L10n.tr("helper.alert.enable_failed.title")
            alert.informativeText = error.localizedDescription
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    private func performHelperSetup(forceRepair: Bool, announceSuccess: Bool, retryPendingOperation: Bool = false) {
        Task { @MainActor in
            do {
                if forceRepair {
                    try await manager.reinstallHelper()
                } else {
                    try await manager.enableHelper()
                }

                if retryPendingOperation {
                    await manager.retryPendingPrivilegedOperationIfNeeded()
                }

                guard announceSuccess else { return }
                let alert = NSAlert()
                alert.messageText = L10n.tr("helper.alert.ready.title")
                alert.informativeText = L10n.tr("helper.alert.ready.message")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.tr("common.ok"))
                alert.runModal()
            } catch let privilegedError as PrivilegedHostsError {
                switch privilegedError {
                case .requiresApproval:
                    presentHelperApprovalAlert(operation: nil)
                case .disabledByUser, .registrationFailed, .repairRequired, .connectionFailed, .timeout:
                    showHelperInstallError(privilegedError)
                }
            } catch {
                showHelperInstallError(error)
            }
        }
    }

    @objc private func handleHelperInterventionNotification(_ notification: Notification) {
        guard !isPresentingHelperInterventionAlert,
              let kindRawValue = notification.userInfo?["kind"] as? String,
              let kind = HelperInterventionKind(rawValue: kindRawValue),
              let operation = notification.userInfo?["operation"] as? String else { return }

        isPresentingHelperInterventionAlert = true
        defer { isPresentingHelperInterventionAlert = false }

        activateApp()

        switch kind {
        case .install:
            if manager.isHelperExplicitlyDisabled {
                let alert = NSAlert()
                alert.messageText = L10n.tr("helper.alert.disabled.title")
                alert.informativeText = L10n.tr("helper.alert.disabled.operation_message", operation)
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.tr("common.enable_now"))
                alert.addButton(withTitle: L10n.tr("common.cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    performHelperSetup(forceRepair: false, announceSuccess: false, retryPendingOperation: true)
                }
            } else {
                presentHelperInstallAlert(operation: operation)
            }
        case .approval:
            presentHelperApprovalAlert(operation: operation)
        case .repair:
            let alert = NSAlert()
            alert.messageText = L10n.tr("helper.alert.repair.title")
            alert.informativeText = L10n.tr("helper.alert.repair.message", operation)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.tr("common.repair_now"))
            alert.addButton(withTitle: L10n.tr("common.later"))
            if alert.runModal() == .alertFirstButtonReturn {
                performHelperSetup(forceRepair: true, announceSuccess: false, retryPendingOperation: true)
            }
        }
    }
}
