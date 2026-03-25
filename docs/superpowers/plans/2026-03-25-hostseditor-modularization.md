# HostsEditor Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract menu bar, status bar, main-window ownership, and helper intervention logic out of `AppDelegate`, split `ViewController` into focused files, and reorganize production/tests into module-based folders without changing app behavior.

**Architecture:** Keep the existing AppKit types and storyboard entry points, but move orchestration into dedicated controllers and split the main interface controller into extension files by responsibility. Use the project's file-system synchronized groups to move files on disk into a new module-oriented tree while preserving target membership.

**Tech Stack:** Swift, AppKit, Combine, SnapKit, Swift Testing, CocoaPods workspace, Xcode file-system synchronized groups

---

## File Structure

### New files

- `HostsEditor/Modules/App/Bootstrap/AppDelegate.swift`
- `HostsEditor/Modules/MainWindow/MainWindowController.swift`
- `HostsEditor/Modules/MenuBar/MainMenuController.swift`
- `HostsEditor/Modules/StatusBar/StatusItemController.swift`
- `HostsEditor/Modules/HelperInstall/HelperInterventionCoordinator.swift`
- `HostsEditor/Modules/MainInterface/ViewController.swift`
- `HostsEditor/Modules/MainInterface/ProfileTableView.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Window.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Layout.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Bindings.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Sidebar.swift`
- `HostsEditor/Modules/MainInterface/ViewController+FindReplace.swift`
- `HostsEditor/Modules/MainInterface/ViewController+ProfileActions.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Delegates.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Testing.swift`

### Moved production files

- `HostsEditor/PreferencesWindowController.swift` -> `HostsEditor/Modules/Preferences/PreferencesWindowController.swift`
- `HostsEditor/Appearance/*` -> `HostsEditor/Modules/Shared/Appearance/*`
- `HostsEditor/Localization/*` -> `HostsEditor/Modules/Shared/Localization/*`
- `HostsEditor/Models/*` -> `HostsEditor/Modules/Shared/Models/*`
- `HostsEditor/Services/*` -> `HostsEditor/Modules/Shared/Services/*`
- `HostsEditor/Storage/*` -> `HostsEditor/Modules/Shared/Storage/*`
- `HostsEditor/Views/*` -> `HostsEditor/Modules/Shared/Views/*`
- `HostsEditor/PrivilegedHelper/*` -> `HostsEditor/Modules/PrivilegedHelper/*`

### Moved test files

- `HostsEditorTests/AppDelegateWindowTests.swift` -> `HostsEditorTests/App/AppDelegateWindowTests.swift`
- `HostsEditorTests/ViewControllerHighlightingTests.swift` -> `HostsEditorTests/MainInterface/ViewControllerHighlightingTests.swift`
- `HostsEditorTests/PreferencesWindowControllerTests.swift` -> `HostsEditorTests/Preferences/PreferencesWindowControllerTests.swift`
- `HostsEditorTests/LocalizationTests.swift` -> `HostsEditorTests/Localization/LocalizationTests.swift`
- `HostsEditorTests/RuntimeLocalizationTests.swift` -> `HostsEditorTests/Localization/RuntimeLocalizationTests.swift`
- `HostsEditorTests/AppSettingsLocalizationTests.swift` -> `HostsEditorTests/Localization/AppSettingsLocalizationTests.swift`
- `HostsEditorTests/AppDatabaseTests.swift` -> `HostsEditorTests/Storage/AppDatabaseTests.swift`
- `HostsEditorTests/BusinessDataMigratorTests.swift` -> `HostsEditorTests/Storage/BusinessDataMigratorTests.swift`
- `HostsEditorTests/HostsManagerDatabaseTests.swift` -> `HostsEditorTests/Services/HostsManagerDatabaseTests.swift`
- `HostsEditorTests/HostsEditorTests.swift` -> `HostsEditorTests/MainInterface/HostsEditorTests.swift`
- `HostsEditorTests/TestSupport.swift` -> `HostsEditorTests/TestSupport/TestSupport.swift`

### Responsibility map

- `AppDelegate.swift` only bootstraps services and controllers.
- `MainWindowController.swift` owns the storyboard-backed window lifetime and reopen-safe presentation.
- `MainMenuController.swift` owns `NSApp.mainMenu`.
- `StatusItemController.swift` owns `NSStatusItem` and its dynamic menu.
- `HelperInterventionCoordinator.swift` owns helper intervention alerts and retries.
- `ViewController+*.swift` files own one UI concern each while preserving the same `ViewController` type.

### Reference docs

- Spec: `docs/superpowers/specs/2026-03-25-hostseditor-modularization-design.md`
- Reference app: `/Users/VanJay/Documents/Work/Private/ViewScope/ViewScope/ViewScope/Modules`

### Common verification commands

- Tests: `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests`
- Archive smoke test: `./scripts/build_dmg.sh --no-notarize`

### Task 1: Pin current bootstrap and main-interface behavior with tests

**Files:**
- Modify: `HostsEditorTests/App/AppDelegateWindowTests.swift`
- Modify: `HostsEditorTests/MainInterface/ViewControllerHighlightingTests.swift`
- Modify: `HostsEditorTests/Preferences/PreferencesWindowControllerTests.swift`
- Modify: `HostsEditorTests/MainInterface/HostsEditorTests.swift`

- [ ] **Step 1: Add failing tests for extracted controller touchpoints**
- [ ] **Step 2: Run `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests/AppDelegateWindowTests -only-testing:HostsEditorTests/ViewControllerHighlightingTests -only-testing:HostsEditorTests/PreferencesWindowControllerTests -only-testing:HostsEditorTests/HostsEditorTests` and confirm at least one new assertion fails for the intended reason**
- [ ] **Step 3: Make only the minimal test harness changes needed so the failures are about missing refactor seams, not broken test setup**
- [ ] **Step 4: Re-run the same focused tests and confirm they are red for the right reason**
- [ ] **Step 5: Commit the red test baseline**

### Task 2: Extract main-window, menu-bar, and status-bar controllers

**Files:**
- Create: `HostsEditor/Modules/MainWindow/MainWindowController.swift`
- Create: `HostsEditor/Modules/MenuBar/MainMenuController.swift`
- Create: `HostsEditor/Modules/StatusBar/StatusItemController.swift`
- Modify: `HostsEditor/Modules/App/Bootstrap/AppDelegate.swift`

- [ ] **Step 1: Write the minimal controller skeletons with the public methods AppDelegate needs**
- [ ] **Step 2: Move main-window ownership and reopen behavior into `MainWindowController`**
- [ ] **Step 3: Move main menu construction into `MainMenuController` and keep localization rebinding there**
- [ ] **Step 4: Move status item creation and menu rebuilding into `StatusItemController`**
- [ ] **Step 5: Run focused tests and a build to confirm the extraction stays green**
- [ ] **Step 6: Commit the bootstrap/menu/status extraction**

### Task 3: Extract helper intervention coordination from AppDelegate

**Files:**
- Create: `HostsEditor/Modules/HelperInstall/HelperInterventionCoordinator.swift`
- Modify: `HostsEditor/Modules/App/Bootstrap/AppDelegate.swift`

- [ ] **Step 1: Add a failing assertion or targeted regression check around helper notification routing if a test seam is practical**
- [ ] **Step 2: Move helper alert presentation, retry state, and activation retry handling into the coordinator**
- [ ] **Step 3: Leave AppDelegate with notification registration and coordinator ownership only**
- [ ] **Step 4: Run focused tests or a full `HostsEditorTests` pass if no isolated seam is available**
- [ ] **Step 5: Commit the helper coordination extraction**

### Task 4: Split ViewController into focused implementation files

**Files:**
- Create: `HostsEditor/Modules/MainInterface/ViewController.swift`
- Create: `HostsEditor/Modules/MainInterface/ProfileTableView.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Window.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Layout.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Bindings.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Sidebar.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+FindReplace.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+ProfileActions.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Delegates.swift`
- Create: `HostsEditor/Modules/MainInterface/ViewController+Testing.swift`

- [ ] **Step 1: Move `ProfileTableView` into its own file without changing behavior**
- [ ] **Step 2: Move window/layout/sidebar helpers into dedicated extension files**
- [ ] **Step 3: Move bindings and localization refresh into `ViewController+Bindings.swift`**
- [ ] **Step 4: Move find/replace behavior into `ViewController+FindReplace.swift`**
- [ ] **Step 5: Move profile add/remove/refresh/context-menu actions into `ViewController+ProfileActions.swift`**
- [ ] **Step 6: Move delegate conformances and testing hooks into their own files**
- [ ] **Step 7: Run focused main-interface tests and confirm the split is behavior-preserving**
- [ ] **Step 8: Commit the ViewController file split**

### Task 5: Reorganize shared production code into module-oriented folders

**Files:**
- Move: shared production files under `HostsEditor/Modules/Shared/*`
- Move: privileged helper files under `HostsEditor/Modules/PrivilegedHelper/*`
- Move: preferences under `HostsEditor/Modules/Preferences/*`

- [ ] **Step 1: Create the new folder tree on disk**
- [ ] **Step 2: Move shared appearance/localization/model/storage/service/view files into their new folders**
- [ ] **Step 3: Move preferences and privileged helper files into their feature folders**
- [ ] **Step 4: Run a build to ensure file-system synchronized groups kept target membership intact**
- [ ] **Step 5: Commit the production folder reorganization**

### Task 6: Reorganize tests to mirror module structure

**Files:**
- Move: test files into `HostsEditorTests/App`, `MainInterface`, `Preferences`, `Localization`, `Storage`, `Services`, `TestSupport`

- [ ] **Step 1: Create the module-mirrored test folders**
- [ ] **Step 2: Move test files into their matching folders**
- [ ] **Step 3: Run `xcodebuild test -workspace HostsEditor.xcworkspace -scheme HostsEditor -destination 'platform=macOS' -only-testing:HostsEditorTests`**
- [ ] **Step 4: Fix any target-discovery or path issues caused by the moves**
- [ ] **Step 5: Commit the test folder reorganization**

### Task 7: Final verification and cleanup

**Files:**
- Modify only if verification reveals issues

- [ ] **Step 1: Run full `HostsEditorTests` again and confirm `** TEST SUCCEEDED **`**
- [ ] **Step 2: Run `./scripts/build_dmg.sh --no-notarize` and confirm archive + DMG generation succeed**
- [ ] **Step 3: Inspect `git status --short` and ensure only intended files remain changed**
- [ ] **Step 4: Prepare a concise summary of the new module layout, extracted controllers, and verification evidence**
