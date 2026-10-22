import Testing
@testable import HostsEditor

@MainActor
struct HelperLaunchdStateTests {
    private func output(programIdentifier: String, extra: String = "") -> String {
        """
        system/cn.vanjay.HostsEditorHelper = {
            active count = 1
            state = running
            program identifier = \(programIdentifier) (mode: 2)
            \(extra)
        }
        """
    }

    @Test
    func healthyHelperDoesNotRequireRepair() {
        let state = HelperLaunchdState(rawOutput: output(programIdentifier: "Contents/MacOS/HostsEditorHelper"))

        #expect(state.programIdentifier == "Contents/MacOS/HostsEditorHelper")
        #expect(!state.shouldForceRepair)
    }

    @Test
    func mismatchedProgramPathRequiresRepair() {
        let state = HelperLaunchdState(rawOutput: output(programIdentifier: "/Applications/Old.app/Contents/MacOS/HostsEditorHelper"))

        #expect(state.shouldForceRepair)
        #expect(state.recoveryMessage == L10n.tr("helper.error.recovery_path_mismatch"))
    }

    @Test
    func spawnFailureAndLWCRUpdateRequireRepair() {
        let spawnFailed = HelperLaunchdState(rawOutput: output(programIdentifier: "Contents/MacOS/HostsEditorHelper", extra: "job state = spawn failed"))
        let needsLWCR = HelperLaunchdState(rawOutput: output(programIdentifier: "Contents/MacOS/HostsEditorHelper", extra: "needs LWCR update"))

        #expect(spawnFailed.isSpawnFailed)
        #expect(spawnFailed.shouldForceRepair)
        #expect(needsLWCR.needsLWCRUpdate)
        #expect(needsLWCR.recoveryMessage == L10n.tr("helper.error.recovery_lwcr_update"))
    }
}

extension HelperLaunchdStateTests {
    @Test
    func missingProgramIdentifierDoesNotForceRepair() {
        let state = HelperLaunchdState(rawOutput: "system/cn.vanjay.HostsEditorHelper = {\n    state = running\n}")

        #expect(state.programIdentifier == nil)
        #expect(!state.shouldForceRepair)
    }
}
