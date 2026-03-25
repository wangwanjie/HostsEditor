import AppKit

@MainActor
final class MainWindowController {
    private let storyboardName = "Main"
    private let windowControllerIdentifier = "WindowController"
    private var windowController: NSWindowController?

    var window: NSWindow? {
        ensureWindowController()?.window
    }

    func showWindow(_ sender: Any?) {
        guard let windowController = ensureWindowController() else { return }
        windowController.showWindow(sender)
        windowController.window?.makeKeyAndOrderFront(sender)
    }

    func closeWindow() {
        ensureWindowController()?.close()
    }

    private func retainExistingWindowControllerIfNeeded() {
        guard windowController == nil else { return }
        let existingController = NSApp.windows
            .compactMap(\.windowController)
            .first(where: { $0.window?.contentViewController is ViewController })
        if let existingController {
            configure(windowController: existingController)
            windowController = existingController
        }
    }

    private func ensureWindowController() -> NSWindowController? {
        retainExistingWindowControllerIfNeeded()
        if let windowController {
            configure(windowController: windowController)
            return windowController
        }

        let storyboard = NSStoryboard(name: storyboardName, bundle: nil)
        guard let windowController = storyboard.instantiateController(withIdentifier: windowControllerIdentifier) as? NSWindowController else {
            return nil
        }

        configure(windowController: windowController)
        self.windowController = windowController
        return windowController
    }

    private func configure(windowController: NSWindowController) {
        windowController.window?.isReleasedWhenClosed = false
    }
}
