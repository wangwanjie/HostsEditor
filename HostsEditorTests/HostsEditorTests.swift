//
//  HostsEditorTests.swift
//  HostsEditorTests
//
//  Created by VanJay on 2026/3/9.
//

import AppKit
import Foundation
import Testing
@testable import HostsEditor

struct HostsEditorTests {

    @Test func releaseVersionIgnoresLeadingVAndTrailingZeros() async throws {
        #expect(ReleaseVersion("v1.0") == ReleaseVersion("1.0.0"))
    }

    @Test func releaseVersionComparesNumericComponents() async throws {
        #expect(ReleaseVersion("1.2.10") > ReleaseVersion("1.2.9"))
    }

    @Test func releaseVersionHandlesPreReleaseSuffixes() async throws {
        #expect(ReleaseVersion("v2.0.0-beta.1") == ReleaseVersion("2.0"))
    }

    @MainActor
    @Test func adjustedEditorFontSizeClampsToUpperBound() async throws {
        #expect(
            AppSettings.adjustedEditorFontSize(
                AppSettings.maxEditorFontSize,
                delta: AppSettings.editorFontSizeStep
            ) == AppSettings.maxEditorFontSize
        )
    }

    @MainActor
    @Test func adjustedEditorFontSizeClampsToLowerBound() async throws {
        #expect(
            AppSettings.adjustedEditorFontSize(
                AppSettings.minEditorFontSize,
                delta: -AppSettings.editorFontSizeStep
            ) == AppSettings.minEditorFontSize
        )
    }

    @MainActor
    @Test func sidebarWidthClampsToSupportedRange() async throws {
        #expect(AppSettings.clampedSidebarWidth(88) == AppSettings.minSidebarWidth)
        #expect(AppSettings.clampedSidebarWidth(999) == AppSettings.maxSidebarWidth)
    }

    @Test func toggleCommentsAddsHashSpaceToSelectedLines() async throws {
        let original = "127.0.0.1 example.test\n127.0.0.1 api.example.test"
        let result = HostsEditorTextEditing.toggleComments(
            in: original,
            selectedRanges: [NSRange(location: 0, length: (original as NSString).length)]
        )

        #expect(result.text == "# 127.0.0.1 example.test\n# 127.0.0.1 api.example.test")
    }

    @Test func toggleCommentsRemovesLeadingWhitespaceAndHashWhenUncommenting() async throws {
        let original = "    # 127.0.0.1 example.test\n# 127.0.0.1 api.example.test"
        let result = HostsEditorTextEditing.toggleComments(
            in: original,
            selectedRanges: [NSRange(location: 0, length: (original as NSString).length)]
        )

        #expect(result.text == "127.0.0.1 example.test\n127.0.0.1 api.example.test")
    }

    @Test func replaceAllMatchesReplacesEveryOccurrence() async throws {
        let original = "127.0.0.1 foo.test\n127.0.0.1 foo.test"
        let result = HostsEditorTextEditing.replaceAllMatches(
            in: original,
            query: "foo.test",
            with: "bar.test"
        )

        #expect(result.text == "127.0.0.1 bar.test\n127.0.0.1 bar.test")
    }

    @MainActor
    @Test func deleteShortcutDoesNotFireWhileFieldEditorIsActive() async throws {
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
    @Test func deleteShortcutStillWorksWhenNoTextInputIsFocused() async throws {
        let nonEditingResponder = NSView()

        #expect(
            !ViewController.isEditingTextInput(
                responder: nonEditingResponder,
                editorTextView: nil,
                editorContainerView: nil
            )
        )
    }

    @Test func sidebarWidthIsNotPersistedBeforeInitialWidthIsApplied() async throws {
        #expect(
            !ViewController.shouldPersistSidebarWidth(
                hasAppliedInitialWidth: false,
                isApplyingStoredWidth: false
            )
        )
    }

    @Test func sidebarWidthIsPersistedAfterInitialWidthIsApplied() async throws {
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
