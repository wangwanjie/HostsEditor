# HostsEditor Persistence, Workspace, and Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move business persistence to GRDB, migrate legacy business data safely, switch release packaging to the CocoaPods workspace, animate preferences window height per tab, fix main-window reopen behavior, and make remote-profile highlighting deterministic.

**Architecture:** Add a dedicated GRDB-backed storage layer under `HostsEditor/Storage/`, migrate business data at launch before shared services consume it, and keep `AppSettings`/`HostsManager` as the UI-facing services. Fix the UI regressions by centralizing main-window ownership in `AppDelegate`, introducing deterministic editor resync and full-document rehighlighting, and making preferences tabs drive animated window resizing.

**Tech Stack:** Swift, AppKit, GRDB via SwiftPM, CocoaPods workspace build, SnapKit, Swift Testing, xcodebuild

---

## File Structure

### New files

- `HostsEditor/Storage/AppDatabase.swift`
- `HostsEditor/Storage/AppDatabaseConfiguration.swift`
- `HostsEditor/Storage/AppSettingRecord.swift`
- `HostsEditor/Storage/ProfileRecord.swift`
- `HostsEditor/Storage/BusinessDataMigrator.swift`
- `HostsEditorTests/AppDatabaseTests.swift`
- `HostsEditorTests/BusinessDataMigratorTests.swift`
- `HostsEditorTests/HostsManagerDatabaseTests.swift`
- `HostsEditorTests/AppDelegateWindowTests.swift`
- `HostsEditorTests/ViewControllerHighlightingTests.swift`

### Modified files

- `HostsEditor.xcodeproj/project.pbxproj`
- `HostsEditor.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `HostsEditor/AppDelegate.swift`
- `HostsEditor/Services/AppSettings.swift`
- `HostsEditor/Services/HostsManager.swift`
- `HostsEditor/Services/UpdateManager.swift`
- `HostsEditor/PreferencesWindowController.swift`
- `HostsEditor/ViewController.swift`
- `HostsEditor/Views/HostsEditorTextView.swift`
- `HostsEditor/Views/HostsSyntaxHighlighter.swift`
- `HostsEditorTests/PreferencesWindowControllerTests.swift`
- `HostsEditorTests/HostsEditorTests.swift`
- `scripts/build_dmg.sh`

### Responsibility map

- `AppDatabase*` files own database location, queue, schema migrations, and typed read/write helpers.
- `BusinessDataMigrator.swift` owns one-time migration from legacy `UserDefaults` business keys into GRDB and clears legacy keys only after readback verification.
- `AppSettings.swift` reads/writes business settings through `AppDatabase`.
- `HostsManager.swift` reads/writes profiles and base hosts content through `AppDatabase`.
- `AppDelegate.swift` owns startup ordering, main-window ownership, and Dock reopen behavior.
- `PreferencesWindowController.swift` owns animated content-height transitions per tab.
- `ViewController.swift` and `HostsEditorTextView.swift` own editor resync and deterministic rehighlighting for remote profile refreshes.
- `scripts/build_dmg.sh` archives from `HostsEditor.xcworkspace`.

### Reference docs

- Spec: `docs/superpowers/specs/2026-03-25-hostseditor-persistence-workspace-and-window-design.md`

### Common verification commands

- Unit tests: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests`
- Resolve packages: `xcodebuild -resolvePackageDependencies -workspace HostsEditor.xcworkspace -scheme HostsEditor`
- Release archive smoke test: `./scripts/build_dmg.sh --no-notarize`

### Task 1: Add GRDB Dependency and Storage Scaffolding

**Files:**
- Create: `HostsEditor/Storage/AppDatabase.swift`
- Create: `HostsEditor/Storage/AppDatabaseConfiguration.swift`
- Create: `HostsEditor/Storage/AppSettingRecord.swift`
- Create: `HostsEditor/Storage/ProfileRecord.swift`
- Modify: `HostsEditor.xcodeproj/project.pbxproj`
- Modify: `HostsEditor.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Test: `HostsEditorTests/AppDatabaseTests.swift`

- [ ] **Step 1: Write the failing database smoke tests**

```swift
import Foundation
import Testing
@testable import HostsEditor

struct AppDatabaseTests {
    @Test func databaseCreatesSchemaAndRoundTripsSettings() throws {
        let database = try AppDatabase.inMemory()

        try database.write { db in
            try database.saveSetting(.appLanguage, value: .string("en"), db: db)
        }

        let value = try database.read { db in
            try database.settingValue(.appLanguage, db: db)
        }

        #expect(value == .string("en"))
    }

    @Test func databaseRoundTripsProfiles() throws {
        let database = try AppDatabase.inMemory()
        let profile = HostsProfile(name: "Local", content: "127.0.0.1 example.test")

        try database.saveProfiles([profile])

        let reloaded = try database.loadProfiles()
        #expect(reloaded == [profile])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/AppDatabaseTests`

Expected: FAIL because `AppDatabase` and the GRDB dependency do not exist yet.

- [ ] **Step 3: Add GRDB to the project and create the minimal storage layer**

```swift
enum AppSettingKey: String {
    case baseSystemContent = "base_system_content"
    case appLanguage = "app_language"
    case appAppearance = "app_appearance"
    case updateCheckStrategy = "update_check_strategy"
    case editorFontSize = "editor_font_size"
    case sidebarWidth = "sidebar_width"
}

struct ProfileRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "profiles"
    var id: String
    var name: String
    var content: String
    var isEnabled: Bool
    var isRemote: Bool
    var remoteURL: String?
    var lastUpdated: Date?
}

final class AppDatabase {
    static let shared = try! AppDatabase(configuration: .appSupportDefault())

    let dbQueue: DatabaseQueue

    init(configuration: AppDatabaseConfiguration) throws {
        self.dbQueue = try DatabaseQueue(path: configuration.databasePath)
        try migrator.migrate(dbQueue)
    }
}
```

- [ ] **Step 4: Run the test to verify the schema and helpers pass**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/AppDatabaseTests`

Expected: PASS for `AppDatabaseTests`.

- [ ] **Step 5: Commit the dependency and storage scaffold**

```bash
git add HostsEditor.xcodeproj/project.pbxproj HostsEditor.xcworkspace/xcshareddata/swiftpm/Package.resolved HostsEditor/Storage HostsEditorTests/AppDatabaseTests.swift
git commit -m "feat: add GRDB storage scaffolding"
```

### Task 2: Migrate Legacy Business Data Before Shared Services Initialize

**Files:**
- Create: `HostsEditor/Storage/BusinessDataMigrator.swift`
- Modify: `HostsEditor/AppDelegate.swift`
- Modify: `HostsEditor/Storage/AppDatabase.swift`
- Modify: `HostsEditor/Storage/AppSettingRecord.swift`
- Test: `HostsEditorTests/BusinessDataMigratorTests.swift`

- [ ] **Step 1: Write the failing migration tests**

```swift
struct BusinessDataMigratorTests {
    @Test func migratorCopiesLegacyBusinessValuesAndClearsLegacyKeys() throws {
        let defaults = UserDefaults(suiteName: "BusinessDataMigratorTests.copy")!
        defaults.removePersistentDomain(forName: "BusinessDataMigratorTests.copy")

        let legacyProfiles = [HostsProfile(name: "Migrated", content: "127.0.0.1 migrated.test")]
        let encoded = try JSONEncoder().encode(legacyProfiles)
        defaults.set(encoded, forKey: "HostsEditorProfiles")
        defaults.set("127.0.0.1 localhost", forKey: "HostsEditorBaseContent")
        defaults.set("english", forKey: "HostsEditorAppLanguage")

        let database = try AppDatabase.inMemory()
        try BusinessDataMigrator(defaults: defaults, database: database).migrateIfNeeded()

        #expect(try database.loadProfiles().count == 1)
        #expect(defaults.object(forKey: "HostsEditorProfiles") == nil)
        #expect(defaults.object(forKey: "HostsEditorBaseContent") == nil)
    }

    @Test func migratorLeavesLegacyKeysIntactWhenVerificationFails() throws {
        // inject a verification failure and assert the legacy keys are still present
    }
}
```

- [ ] **Step 2: Run the migration tests and verify they fail**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/BusinessDataMigratorTests`

Expected: FAIL because migration logic and launch ordering are not implemented yet.

- [ ] **Step 3: Implement the migrator and startup ordering**

```swift
struct BusinessDataMigrator {
    func migrateIfNeeded() throws {
        guard hasLegacyBusinessData else { return }

        let source = try readLegacySnapshot()
        try database.write { db in
            try database.replaceProfiles(source.profiles, db: db)
            try database.saveSettingsSnapshot(source.settings, db: db)
        }

        let reloaded = try database.readBackBusinessSnapshot()
        guard reloaded == source else {
            throw MigrationError.verificationFailed
        }

        clearLegacyBusinessKeys()
    }
}

func applicationDidFinishLaunching(_ notification: Notification) {
    DebugRuntime.start()
    try? AppDatabase.shared.runStartupMigrationIfNeeded()
    _ = AppSettings.shared
    _ = HostsManager.shared
    ...
}
```

- [ ] **Step 4: Run the migration tests again**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/BusinessDataMigratorTests`

Expected: PASS for success and failure-path migration coverage.

- [ ] **Step 5: Commit the migration flow**

```bash
git add HostsEditor/AppDelegate.swift HostsEditor/Storage/AppDatabase.swift HostsEditor/Storage/AppSettingRecord.swift HostsEditor/Storage/BusinessDataMigrator.swift HostsEditorTests/BusinessDataMigratorTests.swift
git commit -m "feat: migrate legacy business data to GRDB"
```

### Task 3: Move AppSettings and HostsManager Business Persistence to GRDB

**Files:**
- Modify: `HostsEditor/Services/AppSettings.swift`
- Modify: `HostsEditor/Services/HostsManager.swift`
- Modify: `HostsEditor/Storage/AppDatabase.swift`
- Modify: `HostsEditor/Storage/ProfileRecord.swift`
- Test: `HostsEditorTests/HostsEditorTests.swift`
- Test: `HostsEditorTests/HostsManagerDatabaseTests.swift`

- [ ] **Step 1: Write the failing service persistence tests**

```swift
struct HostsManagerDatabaseTests {
    @MainActor
    @Test func hostsManagerLoadsProfilesFromDatabase() throws {
        let database = try AppDatabase.inMemory()
        try database.saveProfiles([HostsProfile(name: "DB", content: "127.0.0.1 db.test")])

        let manager = HostsManager(database: database)
        manager.loadProfiles()

        #expect(manager.profiles.map(\.name) == ["DB"])
    }

    @MainActor
    @Test func appSettingsLoadsPersistedValuesFromDatabase() throws {
        let database = try AppDatabase.inMemory()
        try database.saveSetting(.editorFontSize, value: .double(18))

        let settings = AppSettings(database: database)
        #expect(settings.editorFontSize == 18)
    }
}
```

- [ ] **Step 2: Run the service persistence tests and verify they fail**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/HostsManagerDatabaseTests -only-testing:HostsEditorTests/HostsEditorTests`

Expected: FAIL because `AppSettings` and `HostsManager` still read and write business data through `UserDefaults`.

- [ ] **Step 3: Replace business UserDefaults access with AppDatabase access**

```swift
@MainActor
final class AppSettings: ObservableObject {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
        let snapshot = database.loadSettingsSnapshot()
        appLanguage = snapshot.appLanguage ?? Self.defaultLanguage
        ...
    }

    @Published var sidebarWidth: Double {
        didSet { try? database.saveSidebarWidth(sidebarWidth) }
    }
}

@MainActor
final class HostsManager: ObservableObject {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
        loadProfiles()
        baseSystemContent = database.loadBaseSystemContent()
    }
}
```

- [ ] **Step 4: Run the service persistence tests again**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/HostsManagerDatabaseTests -only-testing:HostsEditorTests/HostsEditorTests`

Expected: PASS for database-backed settings/profile persistence with existing behavioral tests still green.

- [ ] **Step 5: Commit the service migration**

```bash
git add HostsEditor/Services/AppSettings.swift HostsEditor/Services/HostsManager.swift HostsEditor/Storage/AppDatabase.swift HostsEditor/Storage/ProfileRecord.swift HostsEditorTests/HostsManagerDatabaseTests.swift HostsEditorTests/HostsEditorTests.swift
git commit -m "feat: back business services with GRDB"
```

### Task 4: Make Remote Profile Editor Refresh and Syntax Highlighting Deterministic

**Files:**
- Modify: `HostsEditor/ViewController.swift`
- Modify: `HostsEditor/Views/HostsEditorTextView.swift`
- Modify: `HostsEditor/Views/HostsSyntaxHighlighter.swift`
- Test: `HostsEditorTests/ViewControllerHighlightingTests.swift`

- [ ] **Step 1: Write the failing editor resync tests**

```swift
struct ViewControllerHighlightingTests {
    @MainActor
    @Test func selectedRemoteProfileRefreshesVisibleEditorContent() async throws {
        let database = try AppDatabase.inMemory()
        let remote = HostsProfile(name: "Remote", content: "127.0.0.1 before.test", isRemote: true, remoteURL: "https://example.com")
        try database.saveProfiles([remote])

        let manager = HostsManager(database: database)
        let controller = ViewController(manager: manager, settings: AppSettings(database: database))
        controller.loadView()
        controller.selectProfileForTesting(id: remote.id)

        manager.updateProfile(id: remote.id, content: "127.0.0.1 after.test")
        controller.handleProfilesDidChangeForTesting()

        #expect(controller.debugEditorString.contains("after.test"))
        #expect(controller.debugDidTriggerFullRehighlight)
    }
}
```

- [ ] **Step 2: Run the resync test and verify it fails**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/ViewControllerHighlightingTests`

Expected: FAIL because profile-model changes do not yet drive deterministic editor resync and full rehighlighting.

- [ ] **Step 3: Implement explicit full rehighlighting and current-selection resync**

```swift
final class HostsEditorTextView: NSTextView {
    private(set) var didTriggerFullRehighlight = false

    func rehighlightEntireDocument() {
        didTriggerFullRehighlight = true
        highlighter.rehighlightEntireDocument()
    }
}

manager.$profiles
    .sink { [weak self] _ in
        self?.reloadTablePreservingSelection()
        self?.refreshEditorIfSelectedProfileChanged()
    }

private func refreshEditorIfSelectedProfileChanged() {
    guard case .profile = selection else { return }
    syncEditorFromSelection()
    editorTextView.rehighlightEntireDocument()
}
```

- [ ] **Step 4: Run the resync test again**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/ViewControllerHighlightingTests`

Expected: PASS and no regressions in existing text-editing behavior.

- [ ] **Step 5: Commit the editor/highlighting fix**

```bash
git add HostsEditor/ViewController.swift HostsEditor/Views/HostsEditorTextView.swift HostsEditor/Views/HostsSyntaxHighlighter.swift HostsEditorTests/ViewControllerHighlightingTests.swift
git commit -m "fix: rehighlight remote profiles after refresh"
```

### Task 5: Animate Preferences Window Height Per Selected Tab

**Files:**
- Modify: `HostsEditor/PreferencesWindowController.swift`
- Modify: `HostsEditorTests/PreferencesWindowControllerTests.swift`

- [ ] **Step 1: Write the failing preferences height test**

```swift
@Suite(.serialized)
struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func preferencesAnimatesWindowHeightWhenSwitchingSections() throws {
        let settings = AppSettings(database: try AppDatabase.inMemory())
        let controller = PreferencesWindowController(updateManager: .shared, settings: settings)
        controller.loadWindow()

        let initialHeight = try #require(controller.window?.frame.height)
        controller.selectSectionForTesting(.helper)

        try waitUntil(description: "preferences resized") {
            guard let updatedHeight = controller.window?.frame.height else { return false }
            return updatedHeight != initialHeight
        }
    }
}
```

- [ ] **Step 2: Run the preferences tests and verify they fail**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/PreferencesWindowControllerTests`

Expected: FAIL because the preferences window currently uses a fixed content size.

- [ ] **Step 3: Replace the fixed-height stack with an animated active-section container**

```swift
private func transition(to section: PreferencesSection, animated: Bool) {
    let targetView = sectionView(for: section)
    install(targetView, in: contentContainerView)

    let targetSize = measuredWindowSize(for: targetView)
    resizeWindow(to: targetSize, animated: animated)
}

private func resizeWindow(to targetSize: NSSize, animated: Bool) {
    guard let window else { return }
    let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
    window.setFrame(adjustedFrameKeepingTopLeft(from: window.frame, to: newFrame), display: true, animate: animated)
}
```

- [ ] **Step 4: Run the preferences tests again**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/PreferencesWindowControllerTests`

Expected: PASS for localization coverage and new height-transition behavior.

- [ ] **Step 5: Commit the preferences window animation**

```bash
git add HostsEditor/PreferencesWindowController.swift HostsEditorTests/PreferencesWindowControllerTests.swift
git commit -m "feat: animate preferences window height per tab"
```

### Task 6: Retain the Main Window Controller and Handle Dock Reopen

**Files:**
- Modify: `HostsEditor/AppDelegate.swift`
- Modify: `HostsEditor/ViewController.swift`
- Test: `HostsEditorTests/AppDelegateWindowTests.swift`

- [ ] **Step 1: Write the failing main-window reopen tests**

```swift
struct AppDelegateWindowTests {
    @MainActor
    @Test func dockReopenShowsMainWindowWhenNoVisibleWindowExists() throws {
        let appDelegate = AppDelegate()
        appDelegate.loadMainWindowControllerForTesting()
        appDelegate.closeMainWindowForTesting()

        let handled = appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)

        #expect(handled)
        #expect(appDelegate.debugMainWindow?.isVisible == true)
    }
}
```

- [ ] **Step 2: Run the main-window tests and verify they fail**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/AppDelegateWindowTests`

Expected: FAIL because the main window controller is not retained and reopen is not centralized.

- [ ] **Step 3: Implement retained window ownership and reopen handling**

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: NSWindowController?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let controller = resolveMainWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: Run the main-window tests again**

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/AppDelegateWindowTests`

Expected: PASS for Dock reopen and retained-controller behavior.

- [ ] **Step 5: Commit the main-window reopen fix**

```bash
git add HostsEditor/AppDelegate.swift HostsEditor/ViewController.swift HostsEditorTests/AppDelegateWindowTests.swift
git commit -m "fix: reopen main window from dock reliably"
```

### Task 7: Switch Release Packaging to the CocoaPods Workspace and Run End-to-End Verification

**Files:**
- Modify: `scripts/build_dmg.sh`
- Modify: `HostsEditor.xcodeproj/project.pbxproj`
- Modify: `HostsEditor.xcworkspace/xcshareddata/swiftpm/Package.resolved`

- [ ] **Step 1: Write the failing packaging expectation as a shell assertion**

```bash
rg -n 'xcodebuild .* -workspace "HostsEditor.xcworkspace"' scripts/build_dmg.sh
```

Expected: no match, because the script still archives from the project entry point.

- [ ] **Step 2: Update the build script to archive from the workspace**

```bash
xcodebuild -workspace "HostsEditor.xcworkspace" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean archive
```

- [ ] **Step 3: Resolve packages and run the full unit test suite**

Run: `xcodebuild -resolvePackageDependencies -workspace HostsEditor.xcworkspace -scheme HostsEditor`
Expected: package resolution succeeds and `GRDB` is present in the workspace dependency graph.

Run: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests`
Expected: PASS for the full unit test bundle.

- [ ] **Step 4: Run a release packaging smoke test**

Run: `./scripts/build_dmg.sh --no-notarize`

Expected: archive and DMG generation succeed from the workspace without notarization.

- [ ] **Step 5: Commit the workspace packaging update**

```bash
git add scripts/build_dmg.sh HostsEditor.xcodeproj/project.pbxproj HostsEditor.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: archive HostsEditor from workspace"
```
