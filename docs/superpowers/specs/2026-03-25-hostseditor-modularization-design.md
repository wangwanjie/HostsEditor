# HostsEditor Modularization Design

## Summary

This design refactors HostsEditor's AppKit surface so menu bar logic, status bar logic, main-window ownership, and helper intervention routing are no longer concentrated in `AppDelegate.swift`, and the oversized `ViewController.swift` is split into focused files without rewriting the screen architecture.

The refactor also reorganizes production code and tests into feature-oriented folders so the repository structure matches runtime responsibilities.

## Goals

- Reduce `AppDelegate.swift` to bootstrap and lifecycle orchestration.
- Extract main menu construction and status item behavior into dedicated controllers, following the same boundary style used in ViewScope.
- Keep main window presentation and reopen handling in a dedicated owner object.
- Split `ViewController.swift` into focused files by feature while preserving the current `ViewController` type and storyboard entry point.
- Reorganize `HostsEditor` and `HostsEditorTests` on disk by module/feature instead of mixed technical buckets.
- Preserve current behavior for localization, helper prompts, status updates, profile editing, find/replace, and tests.

## Non-Goals

- Do not redesign the main UI layout.
- Do not replace AppKit with SwiftUI.
- Do not rewrite the profile editor into multiple child controllers in this pass.
- Do not change persistence behavior beyond what is required to move code into new files/folders.

## Current Problems

### AppDelegate concentration

`HostsEditor/AppDelegate.swift` currently owns all of the following:

- startup sequencing
- main menu creation
- status item creation and dynamic profile menu rebuilding
- helper installation / approval / retry alerts
- main window retention and reopen behavior
- localization rebinding

This makes the file large, hard to test, and expensive to modify safely.

### ViewController concentration

`HostsEditor/ViewController.swift` currently mixes:

- window sizing and autosave
- split-view persistence
- sidebar row mapping
- editor synchronization
- find / replace
- profile add / remove / rename / enable / remote refresh
- table view delegates
- text field delegates
- context menus
- test-only hooks

The type itself is still valid as the main screen controller, but its implementation is too large to reason about comfortably.

### Folder structure mismatch

The current disk layout mixes feature code and shared code:

- root-level `AppDelegate.swift`, `ViewController.swift`, and `PreferencesWindowController.swift`
- `Services/` contains both pure services and editor behavior helpers
- `Views/` contains reusable controls alongside feature-specific UI pieces
- tests are flat even though they cover distinct modules

That structure makes ownership less obvious than it should be.

## Proposed Architecture

## App Bootstrap

Move bootstrap code to:

- `HostsEditor/Modules/App/Bootstrap/AppDelegate.swift`

Responsibilities:

- launch migration and shared service warm-up
- instantiate and retain coordinating controllers
- receive AppKit lifecycle callbacks
- route Dock reopen to the main window controller
- remain the single `@main` entry point

The new `AppDelegate` should not manually build `NSMenu` trees or status item menus.

## Main Menu

Create:

- `HostsEditor/Modules/MenuBar/MainMenuController.swift`

Responsibilities:

- build `NSApp.mainMenu`
- rebuild localized menu titles when language changes
- route menu actions through injected closures or lightweight service dependencies

Dependencies:

- `UpdateManager`
- preferences opening closure
- helper install/uninstall closures
- GitHub/help closure

`AppDelegate` owns the controller lifetime; `MainMenuController` owns the actual menu tree.

## Status Bar

Create:

- `HostsEditor/Modules/StatusBar/StatusItemController.swift`

Responsibilities:

- create and retain `NSStatusItem`
- rebuild the status menu when profiles, loading state, or localization changes
- expose actions for opening the main window, preferences, updates, and profile switching

Dependencies:

- `HostsManager`
- `UpdateManager`
- preferences opening closure
- main-window opening closure

This mirrors the boundary already used by ViewScope's status bar module.

## Main Window Ownership

Create:

- `HostsEditor/Modules/MainWindow/MainWindowController.swift`

Responsibilities:

- load the storyboard-backed main window controller
- retain it strongly
- keep `isReleasedWhenClosed = false`
- expose `showWindow()`, `closeWindow()`, and `window`
- own the reopen-safe presentation path used by menu items, status item, and Dock reopen

`AppDelegate` delegates all main-window presentation work to this object.

## Helper Intervention Coordination

Create:

- `HostsEditor/Modules/HelperInstall/HelperInterventionCoordinator.swift`

Responsibilities:

- observe helper intervention notifications
- present install / approval / repair / disable flows
- own retry-after-activation state

Dependencies:

- `HostsManager`
- `PrivilegedHostsWriter`
- `PreferencesWindowController` only if needed for shared action reuse

This removes alert-heavy business flow from `AppDelegate`.

## Main Interface Refactor

Keep the concrete `ViewController` type but split its implementation into focused files under a feature folder.

Proposed files:

- `HostsEditor/Modules/MainInterface/ViewController.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Window.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Layout.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Bindings.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Sidebar.swift`
- `HostsEditor/Modules/MainInterface/ViewController+FindReplace.swift`
- `HostsEditor/Modules/MainInterface/ViewController+ProfileActions.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Delegates.swift`
- `HostsEditor/Modules/MainInterface/ViewController+Testing.swift`
- `HostsEditor/Modules/MainInterface/ProfileTableView.swift`

Responsibilities:

- base file: stored properties, init, lifecycle, shared private types
- `+Window`: window autosave and sizing
- `+Layout`: UI tree construction
- `+Bindings`: Combine subscriptions, localization refresh, editor resync
- `+Sidebar`: row mapping, selection, sidebar width persistence
- `+FindReplace`: find bar and replace logic
- `+ProfileActions`: add/remove/rename/enable/refresh/profile menu logic
- `+Delegates`: `NSTableView`, `NSTextField`, `NSSplitView`, `NSUserInterfaceValidations`, context menu delegate
- `+Testing`: debug hooks and static helpers

This keeps behavior stable while making each concern readable.

## Folder Layout

Production code target layout:

- `HostsEditor/Modules/App/Bootstrap`
- `HostsEditor/Modules/MainWindow`
- `HostsEditor/Modules/MenuBar`
- `HostsEditor/Modules/StatusBar`
- `HostsEditor/Modules/HelperInstall`
- `HostsEditor/Modules/MainInterface`
- `HostsEditor/Modules/Preferences`
- `HostsEditor/Modules/Shared/Appearance`
- `HostsEditor/Modules/Shared/Localization`
- `HostsEditor/Modules/Shared/Models`
- `HostsEditor/Modules/Shared/Storage`
- `HostsEditor/Modules/Shared/Services`
- `HostsEditor/Modules/Shared/Views`
- `HostsEditor/Modules/PrivilegedHelper`

Tests layout:

- `HostsEditorTests/App`
- `HostsEditorTests/MainInterface`
- `HostsEditorTests/Preferences`
- `HostsEditorTests/Localization`
- `HostsEditorTests/Storage`
- `HostsEditorTests/Services`
- `HostsEditorTests/TestSupport`

## Migration Strategy

Because the project uses file-system synchronized root groups, the refactor can primarily move files on disk and keep target membership synchronized automatically.

Implementation order:

1. Add tests that pin current bootstrap, status item, and main-interface touchpoints.
2. Extract `MainWindowController`, `MainMenuController`, and `StatusItemController`.
3. Extract helper intervention coordination from `AppDelegate`.
4. Move `ViewController` helper types and logic into extension files without changing the storyboard identifier or the class name.
5. Move existing shared files into the new folder tree.
6. Move tests into matching folders.
7. Run full test and packaging verification.

## Testing Strategy

- Add focused tests for the extracted bootstrap/window/status/menu touchpoints where practical.
- Preserve current regression tests for Dock reopen, preferences resizing, localization, persistence, and remote profile highlighting.
- Run full `HostsEditorTests`.
- Run `./scripts/build_dmg.sh --no-notarize` after moves to confirm the workspace/project still archives from the new layout.

## Risks and Mitigations

### Risk: storyboard / selector wiring breaks

Mitigation:

- keep the `ViewController` class name unchanged
- keep `@objc` selectors on the same type even if implementations move to extensions

### Risk: menu or status item behavior regresses during extraction

Mitigation:

- move behavior first, then rename/move folders
- keep controller APIs narrow and closure-driven

### Risk: file moves break target membership

Mitigation:

- rely on file-system synchronized groups
- verify target build immediately after each folder move batch

## Success Criteria

- `AppDelegate.swift` becomes a small bootstrap-focused file.
- Menu bar and status bar logic live in dedicated controllers.
- Main window ownership is centralized outside `AppDelegate`.
- `ViewController.swift` is split into focused module files with the same runtime behavior.
- Production and test folders are grouped by feature/module.
- Full unit tests pass.
- Release DMG smoke build still succeeds from the workspace.
