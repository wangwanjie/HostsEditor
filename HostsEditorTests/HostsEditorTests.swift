//
//  HostsEditorTests.swift
//  HostsEditorTests
//
//  Created by VanJay on 2026/3/9.
//

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

}
