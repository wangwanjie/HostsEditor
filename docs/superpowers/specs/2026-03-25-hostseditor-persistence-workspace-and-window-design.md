# HostsEditor Persistence, Workspace, and Window Behavior Design

## Summary

This design updates HostsEditor in four related areas:

1. Switch release packaging from the project file to the CocoaPods-generated workspace.
2. Move business data persistence from `UserDefaults` to a local SQLite database managed by GRDB.
3. Improve preferences window behavior so the window height animates to match the selected tab.
4. Fix main window reopen behavior after the window has been closed and the user clicks the Dock icon.
5. Fix intermittent syntax highlighting misses when remote profile content is refreshed and shown in the editor.

The implementation keeps runtime flags and operational state outside the database. Only user-facing business data is migrated.

## Goals

- Archive and package the app from `HostsEditor.xcworkspace`.
- Persist business data through GRDB with a clear ownership boundary.
- Migrate existing business data from `UserDefaults` on first launch after upgrade.
- Delete legacy `UserDefaults` business keys immediately after migration is verified by readback.
- Keep settings and profiles loading through stable application-level services.
- Animate preferences window height changes when switching tabs.
- Reopen the main window reliably from Dock and menu actions after it has been closed.
- Make remote profile content rendering and syntax highlighting deterministic after refresh.

## Non-Goals

- Do not move update bookkeeping timestamps into the database.
- Do not move privileged helper disable state into the database.
- Do not redesign the main storyboard or convert the app to a scene-based architecture.
- Do not refactor unrelated UI structure outside the touched flows.

## Current State

### Packaging

`scripts/build_dmg.sh` archives with `xcodebuild -scheme HostsEditor` and does not target the CocoaPods workspace.

### Business Data

Business data is currently split across `UserDefaults`:

- `HostsManager` stores profiles as JSON in `HostsEditorProfiles`.
- `HostsManager` stores base hosts content in `HostsEditorBaseContent`.
- `AppSettings` stores language, appearance, update strategy, editor font size, and sidebar width.

This creates two problems:

- Business data is spread across services without a shared persistence layer.
- Migration becomes harder as the app grows because every service owns its own legacy keys.

### Preferences Window

The preferences window uses a fixed content size and fixed minimum size. Section views are shown and hidden inside a stable frame, so short tabs still occupy the full height.

### Main Window Reopen

The app can create the main window from the storyboard when requested, but the controller is not retained as a stable owner. Reopen logic is fragmented between menu flow and AppKit defaults, which makes Dock-triggered reopen unreliable after the window has been closed.

### Remote Profile Highlighting

Syntax highlighting is attached to the editor text storage and usually updates on character edits. Remote profile refreshes update model state, but editor content refresh and explicit full-range highlighting are not consistently forced for the currently selected remote profile. That makes highlighting failures intermittent.

## Proposed Architecture

### Persistence Layer

Add a focused storage module under `HostsEditor/Storage/`:

- `AppDatabase`
- `BusinessDataMigrator`
- `ProfileRecord`
- `AppSettingRecord`

Responsibilities:

- `AppDatabase` owns the database file location, `DatabaseQueue`, schema migrations, and CRUD entry points.
- `BusinessDataMigrator` reads legacy `UserDefaults` business values, writes them into GRDB, verifies the migrated values, and clears legacy keys only after verification succeeds.
- `ProfileRecord` maps database rows to `HostsProfile`.
- `AppSettingRecord` stores small business settings as key/value records.

Application services become consumers of this layer:

- `HostsManager` reads and writes profile data plus base hosts content through `AppDatabase`.
- `AppSettings` reads and writes business settings through `AppDatabase`.
- `UpdateManager` and privileged helper state continue using `UserDefaults`.

### Database File

Store the SQLite database in the app support directory for the app bundle identifier, for example:

`~/Library/Application Support/HostsEditor/HostsEditor.sqlite`

The storage layer will ensure the directory exists before opening the database.

### Database Schema

Use two tables in the initial version.

#### `profiles`

- `id TEXT PRIMARY KEY`
- `name TEXT NOT NULL`
- `content TEXT NOT NULL`
- `is_enabled INTEGER NOT NULL`
- `is_remote INTEGER NOT NULL`
- `remote_url TEXT`
- `last_updated REAL`

#### `app_settings`

- `key TEXT PRIMARY KEY`
- `value TEXT NOT NULL`

`app_settings` stores:

- `base_system_content`
- `app_language`
- `app_appearance`
- `update_check_strategy`
- `editor_font_size`
- `sidebar_width`

This keeps the first schema small while allowing new settings to be added without a table migration.

## Migration Design

### Trigger Point

Migration runs during app launch before `HostsManager.shared` and `AppSettings.shared` consume business data.

Expected order:

1. Open `AppDatabase`.
2. Run GRDB schema migrations.
3. Run `BusinessDataMigrator`.
4. Initialize services that load business data.

### Source Keys

Legacy business keys:

- `HostsEditorProfiles`
- `HostsEditorBaseContent`
- `HostsEditorUpdateCheckStrategy`
- `HostsEditorAppLanguage`
- `HostsEditorAppAppearance`
- `HostsEditorEditorFontSize`
- `HostsEditorSidebarWidth`

### Migration Algorithm

On launch:

1. Detect whether any legacy business key exists.
2. If no legacy key exists, skip migration.
3. If legacy keys exist, open a database write transaction.
4. Decode legacy profile JSON into `[HostsProfile]`.
5. Normalize empty or missing profile payloads to the current default profile behavior.
6. Write profiles into `profiles`.
7. Write base hosts content and settings into `app_settings`.
8. Read all migrated values back from the database inside the same migration flow.
9. Compare database values to the legacy source values field-by-field.
10. If every value matches, delete legacy business keys from `UserDefaults`.
11. If any step fails, roll back or stop deletion and leave legacy keys intact.

### Verification Rule

“Migration success” means:

- database write succeeded
- readback succeeded
- readback values match the source values

Only then may legacy business keys be deleted.

### Failure Behavior

If migration fails:

- do not delete legacy business keys
- record an error for debugging
- allow the app to continue using values that can still be loaded safely

The implementation should avoid partial deletion under every failure mode.

## Service Changes

### `AppSettings`

`AppSettings` remains the UI-facing observable service, but persistence changes:

- load initial values from `AppDatabase`
- write business changes back to `AppDatabase`
- keep current clamping and side effects for language and appearance

The public API remains mostly unchanged so the rest of the UI does not need broad refactoring.

### `HostsManager`

`HostsManager` continues to own hosts composition, helper coordination, and remote refresh behavior, but persistence changes:

- load profiles from `AppDatabase`
- save profile mutations through `AppDatabase`
- load and persist `baseSystemContent` through `AppDatabase`

This preserves the current responsibilities while removing business `UserDefaults` coupling.

## Preferences Window Design

### Current Problem

Tabs with small content are forced into the same height as larger sections, leaving unnecessary empty space.

### Proposed Behavior

Keep the segmented control and card-like section visuals, but replace the fixed-height presentation with a single active content container:

- the segmented control remains pinned at the top
- only the current section view is hosted in the active container
- each section view reports its fitting height for the fixed window width
- switching tabs animates the window frame height to the new target height
- the content transition also animates so the resize does not feel abrupt

### Constraints

- width remains stable
- minimum width remains fixed
- minimum height becomes the lowest supported content height instead of a constant shared height
- autosaved frame behavior must still work without locking the window to the initial height

## Main Window Reopen Design

### Root Cause

The app currently reopens the main window by instantiating a storyboard controller on demand without retaining it as a stable owner. That is fragile after closing the last window.

### Proposed Behavior

Centralize main window ownership in `AppDelegate`:

- keep a retained main window controller reference
- create or resolve the controller through one code path
- expose a `showMainWindow()` helper that activates the app and shows the window
- route status bar menu open, Dock reopen, and any future reopen path through this helper

### AppKit Hook

Implement:

- `applicationShouldHandleReopen(_:hasVisibleWindows:)`

Behavior:

- if no visible main window exists, call `showMainWindow()`
- return `true` so AppKit treats the reopen action as handled

This makes Dock clicks deterministic after the main window has been closed.

## Remote Profile Highlighting Fix

### Root Cause

Remote profile refresh currently updates model state, but the currently displayed editor content and syntax highlighting are not refreshed through one deterministic path. The highlighter also depends too much on attach-time behavior and character edits.

### Proposed Fix

Apply two coordinated changes:

1. Content synchronization:
   - when profiles change, detect whether the current selection is a profile whose stored content changed
   - if yes, refresh the editor content from the latest model data
   - clear stale pending edits for refreshed remote profiles

2. Explicit full rehighlight:
   - add an editor-facing method that reapplies syntax highlighting across the full document
   - call it whenever the app programmatically replaces editor text after selection changes or remote refreshes

This makes remote refresh, profile switching, and first-load display all share the same deterministic rendering path.

## Packaging Script Changes

Update `scripts/build_dmg.sh` to archive from the workspace:

- use `-workspace HostsEditor.xcworkspace`
- keep `-scheme HostsEditor`
- keep the existing archive, DMG, notarization, and stapling flow

The script should remain conservative and only change the build entry point needed for CocoaPods integration.

## Testing Strategy

### Persistence and Migration

Add tests for:

- loading settings from the database
- saving settings to the database
- loading profiles from the database
- migrating legacy `UserDefaults` business data to the database
- deleting legacy keys only after successful verification
- skipping migration when database data already exists and no legacy keys remain

### Preferences Window

Add tests for:

- switching tabs changes target content height
- window frame height animates to the expected value
- localization-driven segmented widths still update correctly

### Main Window Reopen

Add tests for:

- reopen requests reuse a retained main window controller
- Dock reopen path shows the main window when no visible main window exists

### Remote Highlighting

Add tests for:

- programmatic content replacement triggers a full highlight refresh
- refreshing a selected remote profile updates editor content through the same sync path

## Risks and Mitigations

### Startup Ordering Risk

If shared singletons are initialized before migration completes, the app may cache legacy values too early.

Mitigation:

- move database setup and migration ahead of singleton consumption in launch flow

### Dual Source Drift Risk

If any business code path still writes to `UserDefaults`, the app could recreate split state.

Mitigation:

- remove direct business `UserDefaults` reads and writes from `HostsManager` and `AppSettings`
- keep a narrow list of allowed non-business keys outside the database

### Window Animation Risk

Animated resize can jitter if constraints are applied after the frame change.

Mitigation:

- compute target content size from the active section view before beginning the animation
- keep width fixed during the transition

### Highlighting Regression Risk

Changing editor update flow can interfere with selection, undo grouping, or find result highlighting.

Mitigation:

- preserve existing editor mutation helpers where possible
- rerun find/highlight refresh after programmatic text updates

## Rollout Notes

This work is intended for a single release because the persistence migration, workspace packaging change, and reopen fixes all affect startup and release behavior. Verification must include:

- unit tests
- local app launch with migrated legacy data
- local remote profile refresh validation
- release archive and DMG generation from the workspace
