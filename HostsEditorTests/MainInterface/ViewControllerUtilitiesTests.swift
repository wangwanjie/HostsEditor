import AppKit
import Testing
@testable import HostsEditor

struct ViewControllerUtilitiesTests {
    @MainActor
    @Test
    func deleteShortcutDoesNotFireWhileFieldEditorIsActive() async throws {
        let fieldEditor = NSTextView()

        #expect(
            ViewController.isEditingTextInput(
                responder: fieldEditor,
                editorTextView: nil,
                editorContainerView: nil
            )
        )
    }

    @MainActor
    @Test
    func deleteShortcutStillWorksWhenNoTextInputIsFocused() async throws {
        let nonEditingResponder = NSView()

        #expect(
            !ViewController.isEditingTextInput(
                responder: nonEditingResponder,
                editorTextView: nil,
                editorContainerView: nil
            )
        )
    }

    @Test
    func sidebarWidthIsNotPersistedBeforeInitialWidthIsApplied() async throws {
        #expect(
            !ViewController.shouldPersistSidebarWidth(
                hasAppliedInitialWidth: false,
                isApplyingStoredWidth: false
            )
        )
    }

    @Test
    func sidebarWidthIsPersistedAfterInitialWidthIsApplied() async throws {
        #expect(
            ViewController.shouldPersistSidebarWidth(
                hasAppliedInitialWidth: true,
                isApplyingStoredWidth: false
            )
        )
        #expect(
            !ViewController.shouldPersistSidebarWidth(
                hasAppliedInitialWidth: true,
                isApplyingStoredWidth: true
            )
        )
    }
}
