import AppKit

@MainActor
final class AppearanceManager {
    static let shared = AppearanceManager()

    func resolvedAppearance(for appearance: AppAppearance) -> NSAppearance? {
        appearance.appearance
    }

    func apply(_ appearance: AppAppearance, to application: NSApplication? = nil) {
        let resolvedApplication = application ?? NSApplication.shared
        resolvedApplication.appearance = resolvedAppearance(for: appearance)
    }
}
