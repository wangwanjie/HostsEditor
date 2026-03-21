# HostsEditor Language And Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ProfileSmith-aligned runtime language switching and runtime appearance switching to HostsEditor, covering menus, windows, preferences, alerts, and status-bar UI.

**Architecture:** Introduce centralized `AppLanguage`, `AppAppearance`, `AppLocalization`, `AppearanceManager`, and `L10n` layers, then route existing user-visible strings through them. `AppSettings` persists the selected language and appearance and applies both immediately so open UI updates without restart.

**Tech Stack:** Swift, AppKit, Combine, Testing, Xcode project resources, `Localizable.strings`

---

### Task 1: Add failing tests for language and appearance primitives

**Files:**
- Modify: `HostsEditorTests/HostsEditorTests.swift`
- Create: `HostsEditorTests/LocalizationTests.swift`
- Create: `HostsEditorTests/AppSettingsLocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func appLanguageResolvesSupportedIdentifiers() {
    #expect(AppLanguage.resolve("en-US") == .english)
    #expect(AppLanguage.resolve("zh-CN") == .simplifiedChinese)
    #expect(AppLanguage.resolve("zh-HK") == .traditionalChinese)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests`
Expected: FAIL because `AppLanguage` and related APIs do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditorTests/LocalizationTests.swift HostsEditor/Localization/AppLanguage.swift
git commit -m "test: add localization primitives"
```

### Task 2: Add runtime localization and appearance managers

**Files:**
- Create: `HostsEditor/Localization/AppLanguage.swift`
- Create: `HostsEditor/Localization/AppLocalization.swift`
- Create: `HostsEditor/Localization/L10n.swift`
- Create: `HostsEditor/Appearance/AppAppearance.swift`
- Create: `HostsEditor/Appearance/AppearanceManager.swift`
- Create: `HostsEditor/en.lproj/Localizable.strings`
- Create: `HostsEditor/zh-Hans.lproj/Localizable.strings`
- Create: `HostsEditor/zh-Hant.lproj/Localizable.strings`
- Modify: `HostsEditor.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func localizationReturnsUpdatedStringsAfterLanguageSwitch() {
    let localization = AppLocalization(bundle: .main, initialLanguage: .simplifiedChinese)
    #expect(localization.string("menu.preferences") == "偏好设置…")
    localization.setLanguage(.english)
    #expect(localization.string("menu.preferences") == "Preferences…")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests/localizationReturnsUpdatedStringsAfterLanguageSwitch`
Expected: FAIL because bundles and runtime localization do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
final class AppLocalization: ObservableObject {
    @Published private(set) var language: AppLanguage
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditor/Localization HostsEditor/Appearance HostsEditor/*.lproj HostsEditor.xcodeproj/project.pbxproj HostsEditorTests/LocalizationTests.swift
git commit -m "feat: add runtime localization and appearance managers"
```

### Task 3: Extend AppSettings and startup ordering

**Files:**
- Modify: `HostsEditor/Services/AppSettings.swift`
- Modify: `HostsEditor/AppDelegate.swift`
- Modify: `HostsEditorTests/HostsEditorTests.swift`
- Modify: `HostsEditorTests/AppSettingsLocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func appSettingsPersistsLanguageAndAppearanceAndAppliesThem() {
    let defaults = UserDefaults(suiteName: "HostsEditorTests.Settings")!
    let settings = AppSettings(defaults: defaults)
    settings.appLanguage = .english
    settings.appAppearance = .dark
    #expect(defaults.string(forKey: "HostsEditorAppLanguage") == "en")
    #expect(AppLocalization.shared.language == .english)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/AppSettingsLocalizationTests`
Expected: FAIL because the settings object does not expose language and appearance yet

- [ ] **Step 3: Write minimal implementation**

```swift
@Published var appLanguage: AppLanguage
@Published var appAppearance: AppAppearance
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/AppSettingsLocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditor/Services/AppSettings.swift HostsEditor/AppDelegate.swift HostsEditorTests/AppSettingsLocalizationTests.swift
git commit -m "feat: persist language and appearance settings"
```

### Task 4: Add failing UI refresh tests for Preferences and main window

**Files:**
- Create: `HostsEditorTests/PreferencesWindowControllerTests.swift`
- Create: `HostsEditorTests/RuntimeLocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func preferencesRefreshesLocalizedTitlesWhenLanguageChanges() throws {
    let controller = PreferencesWindowController.testInstance()
    controller.showWindow(nil)
    AppLocalization.shared.setLanguage(.english)
    #expect(controller.window?.title == "Preferences")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/PreferencesWindowControllerTests -only-testing:HostsEditorTests/RuntimeLocalizationTests`
Expected: FAIL because UI does not observe runtime language changes yet

- [ ] **Step 3: Write minimal implementation**

```swift
AppLocalization.shared.$language
    .sink { [weak self] _ in
        self?.applyLocalization()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/PreferencesWindowControllerTests -only-testing:HostsEditorTests/RuntimeLocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditorTests/PreferencesWindowControllerTests.swift HostsEditorTests/RuntimeLocalizationTests.swift
git commit -m "test: cover runtime UI localization refresh"
```

### Task 5: Localize and refresh Preferences window dynamically

**Files:**
- Modify: `HostsEditor/PreferencesWindowController.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func preferencesShowsLocalizedLanguageAndAppearanceControls() {
    let controller = PreferencesWindowController.testInstance()
    controller.loadWindow()
    #expect(controller.debugLanguagePopup.itemTitles == ["English", "简体中文", "繁體中文"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/PreferencesWindowControllerTests`
Expected: FAIL because the new controls and localized titles do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
private let languagePopup = NSPopUpButton()
private let appearancePopup = NSPopUpButton()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/PreferencesWindowControllerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditor/PreferencesWindowController.swift HostsEditorTests/PreferencesWindowControllerTests.swift
git commit -m "feat: localize preferences and add language appearance controls"
```

### Task 6: Localize and refresh menus, status menu, and alerts dynamically

**Files:**
- Modify: `HostsEditor/AppDelegate.swift`
- Modify: `HostsEditor/Services/UpdateManager.swift`
- Modify: `HostsEditor/PrivilegedHelper/PrivilegedHostsWriter.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func updateStrategyTitlesFollowCurrentLanguage() {
    AppLocalization.shared.setLanguage(.english)
    #expect(UpdateCheckStrategy.manual.title == "Manual")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests/updateStrategyTitlesFollowCurrentLanguage`
Expected: FAIL because enum titles and alert strings are still hardcoded

- [ ] **Step 3: Write minimal implementation**

```swift
var title: String {
    switch self {
    case .manual: return L10n.updateStrategyManual
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/LocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditor/AppDelegate.swift HostsEditor/Services/UpdateManager.swift HostsEditor/PrivilegedHelper/PrivilegedHostsWriter.swift HostsEditor/Services/AppSettings.swift HostsEditorTests/LocalizationTests.swift
git commit -m "feat: localize menus and alerts"
```

### Task 7: Localize and refresh main window controls dynamically

**Files:**
- Modify: `HostsEditor/ViewController.swift`
- Modify: `HostsEditor/Views/EditorFindBarView.swift`
- Modify: `HostsEditor/Views/ProfileCellView.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func mainViewRefreshesLocalizedControlsWhenLanguageChanges() throws {
    let controller = ViewController()
    controller.loadViewIfNeeded()
    AppLocalization.shared.setLanguage(.english)
    #expect(controller.debugApplyButton.title == "Save and Apply")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/RuntimeLocalizationTests`
Expected: FAIL because main-window controls do not update after runtime language switch

- [ ] **Step 3: Write minimal implementation**

```swift
private func applyLocalization() {
    applyButton.title = L10n.mainSaveAndApply
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests/RuntimeLocalizationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HostsEditor/ViewController.swift HostsEditor/Views/EditorFindBarView.swift HostsEditor/Views/ProfileCellView.swift HostsEditorTests/RuntimeLocalizationTests.swift
git commit -m "feat: localize main window and find bar"
```

### Task 8: Run full verification and clean up

**Files:**
- Modify: `HostsEditor.xcodeproj/project.pbxproj`
- Modify: `HostsEditorTests/*.swift`
- Modify: `HostsEditor/**/*.swift`

- [ ] **Step 1: Run targeted tests**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor -only-testing:HostsEditorTests`
Expected: PASS

- [ ] **Step 2: Run full scheme tests**

Run: `xcodebuild test -project HostsEditor.xcodeproj -scheme HostsEditor`
Expected: PASS

- [ ] **Step 3: Verify no remaining hardcoded UI strings in production code**

Run: `rg -n --glob '*.swift' '[\\p{Han}]' HostsEditor`
Expected: only comments or intentionally untranslated non-UI content remain

- [ ] **Step 4: Review resources and project wiring**

Run: `rg -n 'Localizable.strings|en.lproj|zh-Hans.lproj|zh-Hant.lproj' HostsEditor.xcodeproj/project.pbxproj`
Expected: localized resources are included in the app target

- [ ] **Step 5: Commit**

```bash
git add HostsEditor HostsEditorTests HostsEditor.xcodeproj/project.pbxproj
git commit -m "feat: add dynamic language and appearance support"
```
