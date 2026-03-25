import Foundation

@MainActor
func waitUntil(
    timeout: TimeInterval = 5,
    description: String,
    condition: @escaping () -> Bool
) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    if !condition() {
        throw NSError(
            domain: "HostsEditorTests.Timeout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Condition '\(description)' was not satisfied within \(timeout) seconds."]
        )
    }
}
