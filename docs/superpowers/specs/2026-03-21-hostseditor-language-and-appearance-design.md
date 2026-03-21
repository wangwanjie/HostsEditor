# HostsEditor Dynamic Language and Appearance Design

Date: 2026-03-21

## Goal

Add runtime language switching and runtime appearance switching to HostsEditor.

The supported languages are:

- English
- Simplified Chinese
- Traditional Chinese

The supported appearance modes are:

- Follow System
- Light
- Dark

The feature must cover:

- Main app UI
- App menu
- Status bar menu
- Preferences window
- Update alerts
- Helper-installation and helper-repair alerts

## Confirmed Scope

### In Scope

- Persist selected app language in user defaults
- Persist selected app appearance in user defaults
- Apply language changes immediately in the running app without restart
- Apply appearance changes immediately in the running app without restart
- Add language and appearance controls to Preferences
- Localize the current main app UI strings that are user-visible
- Keep the strategy, defaults, and runtime behavior aligned with ProfileSmith

### Out of Scope

- Refactoring unrelated hosts-management logic
- Reworking the current visual design beyond the controls needed for language and appearance
- Adding extra languages or appearance modes beyond the three confirmed choices
- Changing the status item icon or syntax-highlighting palette design

## Design Summary

Use the same centralized model as ProfileSmith.

- `AppSettings` remains the persistence entry point for user-facing preferences
- `AppLocalization` becomes the single runtime source of truth for current app language
- `AppearanceManager` becomes the single runtime source of truth for current app appearance
- `L10n` becomes the typed access layer for localized strings

This keeps behavior consistent across menus, windows, alerts, and future UI additions.

## Architecture

### `AppLanguage`

Add a language enum with:

- `english = "en"`
- `simplifiedChinese = "zh-Hans"`
- `traditionalChinese = "zh-Hant"`

Responsibilities:

- Resolve stored identifiers into supported languages
- Resolve `Locale.preferredLanguages` into the closest supported language
- Provide locale information for string formatting

### `AppAppearance`

Add an appearance enum with:

- `system`
- `light`
- `dark`

Responsibilities:

- Represent the selected preference
- Map to the correct `NSAppearance` value

### `AppLocalization`

Add a shared localization manager that:

- Stores the current `AppLanguage`
- Resolves the matching localized bundle
- Returns localized strings by key
- Formats parameterized strings using the active locale

`AppLocalization` is the only runtime language source used by the app process.

### `L10n`

Add a typed localization wrapper around string keys.

Responsibilities:

- Hold typed accessors for app-menu strings
- Hold typed accessors for preferences strings
- Hold typed accessors for main window strings
- Hold typed accessors for status bar menu strings
- Hold typed accessors for update and helper alerts
- Hold formatting helpers for dynamic strings such as version numbers, profile names, operation names, and error messages

### `AppearanceManager`

Add a shared appearance manager that:

- Receives `AppAppearance`
- Applies it to `NSApp.appearance`
- Uses:
  - `nil` for system
  - `.aqua` for light
  - `.darkAqua` for dark

No controller should own a separate appearance state.

### `AppSettings`

Extend the existing settings object with:

- `appLanguage`
- `appAppearance`
- existing `updateCheckStrategy`
- existing editor and sidebar preferences

Responsibilities:

- Load persisted values or defaults on startup
- Persist new values immediately on change
- Forward language changes to `AppLocalization.shared`
- Forward appearance changes to `AppearanceManager.shared`

Startup order must apply language and appearance before building menus and presenting windows.

## UI Integration

### Preferences

Expand Preferences to include a General section containing:

- Language
- Appearance

Keep the existing sections for:

- Updates
- Editor
- Helper

Behavior:

- Selecting a language updates open windows immediately
- Selecting an appearance updates open windows immediately
- No restart prompt

### App Menu

Rebuild the app menu when language changes.

Reason:

- The menu is created once at launch
- Rebuilding is simpler and less error-prone than mutating many existing menu items

### Status Bar Menu

Rebuild the status bar menu when:

- profiles change
- language changes

The profile list stays data-driven. Only user-facing labels become localized.

### Main Window

The main window controller should expose an `applyLocalization()` path that updates:

- window title
- sidebar column title
- top-level buttons
- find/replace bar labels and placeholders
- popover controls
- context menus
- section headers and read-only labels

Existing data rendering stays intact. Only user-visible strings move behind `L10n`.

### Alerts

All alerts should fetch localized strings at presentation time so language switching does not leave stale strings in later dialogs.

Covered alert groups:

- update checks
- helper enable/disable/repair/approval
- profile deletion
- remote-refresh validation errors

## Resource Strategy

Add `Localizable.strings` resources for:

- `en.lproj`
- `zh-Hans.lproj`
- `zh-Hant.lproj`

These resources only need to be included in the main app target for HostsEditor.

## Data Flow

### Startup

1. `AppSettings` loads persisted values or defaults
2. `AppLocalization.shared` applies the selected language
3. `AppearanceManager.shared` applies the selected appearance
4. `AppDelegate` builds menus and wires windows

### Runtime Language Switch

1. User changes language in Preferences
2. `AppSettings.appLanguage` persists the new value
3. `AppLocalization.shared` publishes the new language
4. App menu rebuilds
5. Status bar menu rebuilds
6. Open windows refresh localized UI

### Runtime Appearance Switch

1. User changes appearance in Preferences
2. `AppSettings.appAppearance` persists the new value
3. `AppearanceManager.shared` applies the chosen `NSAppearance`
4. AppKit updates effective appearance for the app
5. Existing appearance-aware views refresh naturally

## Testing Strategy

Add tests for:

- `AppLanguage.resolve` and `AppLanguage.preferred`
- `AppSettings` persistence and language/appearance side effects
- `AppLocalization` runtime string lookup after language changes
- `AppearanceManager` application behavior
- `PreferencesWindowController` dynamic language and appearance controls
- Main window runtime localization refresh for representative controls

The implementation should follow TDD:

1. Add the failing test
2. Verify it fails for the expected reason
3. Add minimal production code
4. Verify it passes

