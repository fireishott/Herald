import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    var preset: ThemePreset = .nous
    var colorSchemePreference: ColorSchemePreference = .system

    func resolvedColorScheme(for systemScheme: ColorScheme) -> ColorScheme {
        switch colorSchemePreference {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    func currentPalette(for systemScheme: ColorScheme) -> ThemePalette {
        let resolved = resolvedColorScheme(for: systemScheme)
        return preset.colors(for: resolved)
    }

    func load(from settings: UserSettings) {
        preset = settings.themePreset
        colorSchemePreference = settings.colorSchemePreference
    }

    func save(to settings: inout UserSettings) {
        settings.themePreset = preset
        settings.colorSchemePreference = colorSchemePreference
    }
}
