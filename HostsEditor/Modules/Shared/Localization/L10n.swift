import Foundation

enum L10n {
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.string(key, arguments: arguments)
    }

    static var appName: String { tr("app.name") }
    static var menuPreferences: String { tr("menu.preferences") }

    static var updateStrategyManual: String { tr("settings.update.manual") }
    static var updateStrategyDaily: String { tr("settings.update.daily") }
    static var updateStrategyOnLaunch: String { tr("settings.update.on_launch") }

    static var settingsLanguageEnglish: String { tr("settings.language.english") }
    static var settingsLanguageSimplified: String { tr("settings.language.simplified") }
    static var settingsLanguageTraditional: String { tr("settings.language.traditional") }
    static var settingsAppearanceSystem: String { tr("settings.appearance.system") }
    static var settingsAppearanceLight: String { tr("settings.appearance.light") }
    static var settingsAppearanceDark: String { tr("settings.appearance.dark") }

    static var preferencesWindowTitle: String { tr("preferences.window.title") }
    static var preferencesSectionGeneral: String { tr("preferences.section.general") }
    static var preferencesSectionUpdates: String { tr("preferences.section.updates") }
    static var preferencesSectionEditor: String { tr("preferences.section.editor") }
    static var preferencesSectionHelper: String { tr("preferences.section.helper") }
    static var preferencesLanguage: String { tr("preferences.language") }
    static var preferencesAppearance: String { tr("preferences.appearance") }
    static var preferencesUpdateCheckStrategy: String { tr("preferences.update_check_strategy") }
    static var preferencesEditorFontSize: String { tr("preferences.editor_font_size") }
    static var preferencesCurrentStatus: String { tr("preferences.current_status") }
    static var preferencesAutoDownloads: String { tr("preferences.auto_downloads") }
    static var preferencesAutoDownloadsAvailable: String { tr("preferences.auto_downloads.available") }
    static var preferencesAutoDownloadsUnavailable: String { tr("preferences.auto_downloads.unavailable") }
    static var preferencesAutoDownloadsManual: String { tr("preferences.auto_downloads.manual") }
    static var preferencesCheckForUpdatesNow: String { tr("preferences.check_updates_now") }
    static var preferencesResetDefaults: String { tr("preferences.reset_defaults") }
    static var preferencesRepairHelper: String { tr("preferences.repair_helper") }
    static var preferencesDisableHelper: String { tr("preferences.disable_helper") }
    static var preferencesOpenLoginItems: String { tr("preferences.open_login_items") }

    static var helperStatusDisabled: String { tr("helper.status.disabled") }
    static var helperStatusEnabled: String { tr("helper.status.enabled") }
    static var helperStatusPending: String { tr("helper.status.pending") }
    static var helperStatusNotEnabled: String { tr("helper.status.not_enabled") }
    static var helperStatusUnknown: String { tr("helper.status.unknown") }
    static var helperDetailDisabled: String { tr("helper.detail.disabled") }
    static var helperDetailEnabled: String { tr("helper.detail.enabled") }
    static var helperDetailPending: String { tr("helper.detail.pending") }
    static var helperDetailNotEnabled: String { tr("helper.detail.not_enabled") }
    static var helperDetailUnknown: String { tr("helper.detail.unknown") }

    static var mainProfiles: String { tr("main.profiles") }
    static var mainAdd: String { tr("main.add") }
    static var mainDelete: String { tr("main.delete") }
    static var mainSaveAndApply: String { tr("main.save_and_apply") }
    static var mainRefresh: String { tr("main.refresh") }
    static var mainRefreshRemote: String { tr("main.refresh_remote") }
    static var mainLocalProfile: String { tr("main.local_profile") }
    static var mainRemoteProfile: String { tr("main.remote_profile") }
    static var mainNewProfileName: String { tr("main.new_profile_name") }
    static var mainRemoteURL: String { tr("main.remote_url") }
    static var mainRemoteURLPlaceholder: String { tr("main.remote_url_placeholder") }
    static var mainAddRemoteConfirm: String { tr("main.add_remote_confirm") }
    static var mainRemoteURLEmpty: String { tr("main.remote_url_empty") }
    static func mainDeleteProfileTitle(_ name: String) -> String { tr("main.delete_profile.title", name) }
    static var mainDeleteProfileMessage: String { tr("main.delete_profile.message") }
    static var mainSectionLocal: String { tr("main.section.local") }
    static var mainSectionRemote: String { tr("main.section.remote") }
    static var mainSystem: String { tr("main.system") }
    static var mainDefault: String { tr("main.default") }
    static var mainContextEnable: String { tr("main.context.enable") }
    static var mainContextDisable: String { tr("main.context.disable") }
    static var mainContextDelete: String { tr("main.context.delete") }

    static var findPlaceholder: String { tr("find.placeholder") }
    static var replacePlaceholder: String { tr("replace.placeholder") }
    static var replaceButton: String { tr("replace.button") }
    static var replaceAllButton: String { tr("replace_all.button") }
    static var accessibilityPreviousResult: String { tr("accessibility.previous_result") }
    static var accessibilityNextResult: String { tr("accessibility.next_result") }
    static var accessibilityCloseFind: String { tr("accessibility.close_find") }

    static func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .english:
            return settingsLanguageEnglish
        case .simplifiedChinese:
            return settingsLanguageSimplified
        case .traditionalChinese:
            return settingsLanguageTraditional
        }
    }

    static func appearanceName(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system:
            return settingsAppearanceSystem
        case .light:
            return settingsAppearanceLight
        case .dark:
            return settingsAppearanceDark
        }
    }
}
