import Cocoa

extension ViewController {
    func configureWindowIfNeeded() {
        guard let window = view.window else { return }
        window.isRestorable = false
        window.minSize = NSSize(width: 800, height: 500)
        guard !didConfigureWindowFrameAutosave else { return }
        didConfigureWindowFrameAutosave = true

        let restored = window.setFrameUsingName(Self.mainWindowFrameAutosaveName)
        _ = window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)
        if !restored {
            window.setContentSize(NSSize(width: 1040, height: 680))
            window.center()
        }
    }
}
