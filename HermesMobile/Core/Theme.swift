import SwiftUI

// MARK: - App Theme
// Ports all 21 hermes-webui skins to iOS.
// Each theme defines a cohesive dark-mode palette.

enum AppTheme: String, Codable, CaseIterable, Hashable, Sendable {
    case `default`
    case ares
    case mono
    case graphite
    case codex
    case terracotta
    case catppuccin
    case charizard
    case geistContrast = "geist-contrast"
    case github
    case hepburn
    case neon
    case neonSoft = "neon-soft"
    case neonPaint = "neon-paint"
    case nous
    case poseidon
    case sienna
    case sisyphus
    case slate
    case verdigris
    case zeus

    /// The live shared theme. Updated by `SettingsStore` whenever the user
    /// changes their preference so that `Design.Colors` computed properties
    /// return the correct palette on the next view-body evaluation.
    nonisolated(unsafe) static var shared: AppTheme = .default

    // MARK: - Display

    var displayName: String {
        switch self {
        case .`default`:  return "Default"
        case .ares:       return "Ares"
        case .mono:       return "Mono"
        case .graphite:   return "Graphite"
        case .codex:      return "Codex"
        case .terracotta: return "Terracotta"
        case .catppuccin: return "Catppuccin"
        case .charizard:  return "Charizard"
        case .geistContrast: return "Geist Contrast"
        case .github:     return "GitHub"
        case .hepburn:    return "Hepburn"
        case .neon:       return "Neon"
        case .neonSoft:   return "Neon Soft"
        case .neonPaint:  return "Neon Paint"
        case .nous:       return "Nous"
        case .poseidon:   return "Poseidon"
        case .sienna:     return "Sienna"
        case .sisyphus:   return "Sisyphus"
        case .slate:      return "Slate"
        case .verdigris:  return "Verdigris"
        case .zeus:       return "Zeus"
        }
    }

    var subtitle: String {
        switch self {
        case .`default`:  return "Gold"
        case .ares:       return "Red"
        case .mono:       return "Gray"
        case .graphite:   return "Neutral"
        case .codex:      return "Green"
        case .terracotta: return "Warm Earth"
        case .catppuccin: return "Purple Pastel"
        case .charizard:  return "Fire"
        case .geistContrast: return "High Contrast"
        case .github:     return "Developer"
        case .hepburn:    return "Elegance"
        case .neon:       return "Electric Purple"
        case .neonSoft:   return "Muted Purple"
        case .neonPaint:  return "Hot Pink"
        case .nous:       return "Nous Branded"
        case .poseidon:   return "Ocean"
        case .sienna:     return "Warm Earth"
        case .sisyphus:   return "Dark Gold"
        case .slate:      return "Cool Gray"
        case .verdigris:  return "Patina"
        case .zeus:       return "OLED"
        }
    }

    var icon: String {
        switch self {
        case .`default`:  return "star.fill"
        case .ares:       return "flame.fill"
        case .mono:       return "circle.fill"
        case .graphite:   return "diamond.fill"
        case .codex:      return "leaf.fill"
        case .terracotta: return "sun.max.fill"
        case .catppuccin: return "moon.stars.fill"
        case .charizard:  return "flame.circle.fill"
        case .geistContrast: return "bolt.fill"
        case .github:     return "chevron.left.forwardslash.chevron.right"
        case .hepburn:    return "sparkles"
        case .neon:       return "light.max"
        case .neonSoft:   return "lightbulb.fill"
        case .neonPaint:  return "paintbrush.fill"
        case .nous:       return "brain.head.profile"
        case .poseidon:   return "drop.fill"
        case .sienna:     return "mountain.2.fill"
        case .sisyphus:   return "arrow.triangle.2.circlepath"
        case .slate:      return "square.fill"
        case .verdigris:  return "leaf.arrow.triangle.circlepath"
        case .zeus:       return "bolt.circle.fill"
        }
    }

    // MARK: - Color Palette

    /// Main background color.
    var background: Color {
        switch self {
        case .`default`:     return Color(hex: 0x0D0D1A)
        case .ares:          return Color(hex: 0x0D0D1A)
        case .mono:          return Color(hex: 0x1A1A1A)
        case .graphite:      return Color(hex: 0x1E1E1E)
        case .codex:         return Color(hex: 0x0D1A14)
        case .terracotta:    return Color(hex: 0x1A1410)
        case .catppuccin:    return Color(hex: 0x1E1E2E)
        case .charizard:     return Color(hex: 0x1A0D0D)
        case .geistContrast: return Color(hex: 0x0A0A0A)
        case .github:        return Color(hex: 0x0D1117)
        case .hepburn:       return Color(hex: 0x1A1520)
        case .neon:          return Color(hex: 0x0D0D1A)
        case .neonSoft:      return Color(hex: 0x141420)
        case .neonPaint:     return Color(hex: 0x1A0D14)
        case .nous:          return Color(hex: 0x0D0D14)
        case .poseidon:      return Color(hex: 0x0D141A)
        case .sienna:        return Color(hex: 0x1A140D)
        case .sisyphus:      return Color(hex: 0x141414)
        case .slate:         return Color(hex: 0x141820)
        case .verdigris:     return Color(hex: 0x0D1A14)
        case .zeus:          return Color(hex: 0x000000)
        }
    }

    /// Sidebar / navigation background.
    var sidebar: Color {
        switch self {
        case .`default`:     return Color(hex: 0x141425)
        case .ares:          return Color(hex: 0x1A1020)
        case .mono:          return Color(hex: 0x222222)
        case .graphite:      return Color(hex: 0x252525)
        case .codex:         return Color(hex: 0x142520)
        case .terracotta:    return Color(hex: 0x251E18)
        case .catppuccin:    return Color(hex: 0x282838)
        case .charizard:     return Color(hex: 0x251414)
        case .geistContrast: return Color(hex: 0x111111)
        case .github:        return Color(hex: 0x161B22)
        case .hepburn:       return Color(hex: 0x231E28)
        case .neon:          return Color(hex: 0x141428)
        case .neonSoft:      return Color(hex: 0x1C1C2C)
        case .neonPaint:     return Color(hex: 0x251420)
        case .nous:          return Color(hex: 0x141420)
        case .poseidon:      return Color(hex: 0x142028)
        case .sienna:        return Color(hex: 0x252018)
        case .sisyphus:      return Color(hex: 0x1E1E1E)
        case .slate:         return Color(hex: 0x1C2028)
        case .verdigris:     return Color(hex: 0x142520)
        case .zeus:          return Color(hex: 0x0A0A0A)
        }
    }

    /// Elevated surface for cards and panels. Derived as a subtle
    /// lightening of the sidebar color.
    var surface: Color {
        sidebar.opacity(0.65)
    }

    /// Primary foreground text.
    var foreground: Color {
        switch self {
        case .`default`:     return Color(hex: 0xFFF8DC)
        case .ares:          return Color(hex: 0xFFE0E0)
        case .mono:          return Color(hex: 0xE0E0E0)
        case .graphite:      return Color(hex: 0xD7D6CE)
        case .codex:         return Color(hex: 0xE0FFE0)
        case .terracotta:    return Color(hex: 0xFFE8D6)
        case .catppuccin:    return Color(hex: 0xCDD6F4)
        case .charizard:     return Color(hex: 0xFFD4B8)
        case .geistContrast: return Color(hex: 0xFAFAFA)
        case .github:        return Color(hex: 0xC9D1D9)
        case .hepburn:       return Color(hex: 0xF0E6F6)
        case .neon:          return Color(hex: 0xE8E0FF)
        case .neonSoft:      return Color(hex: 0xE8E0FF)
        case .neonPaint:     return Color(hex: 0xFFE0F0)
        case .nous:          return Color(hex: 0xE8E0FF)
        case .poseidon:      return Color(hex: 0xE0F0FF)
        case .sienna:        return Color(hex: 0xFFE8D0)
        case .sisyphus:      return Color(hex: 0xE0D8C8)
        case .slate:         return Color(hex: 0xC8D0D8)
        case .verdigris:     return Color(hex: 0xD0E8D8)
        case .zeus:          return Color(hex: 0xFFF8DC)
        }
    }

    /// Muted foreground at reduced contrast.
    var secondaryForeground: Color {
        foreground.opacity(0.6)
    }

    /// Accent / brand color.
    var accent: Color {
        switch self {
        case .`default`:     return Color(hex: 0xFFD700)
        case .ares:          return Color(hex: 0xFF4444)
        case .mono:          return Color(hex: 0xCCCCCC)
        case .graphite:      return Color(hex: 0xA0A0A0)
        case .codex:         return Color(hex: 0x72B39A)
        case .terracotta:    return Color(hex: 0xD97757)
        case .catppuccin:    return Color(hex: 0xCBA6F7)
        case .charizard:     return Color(hex: 0xFF6B35)
        case .geistContrast: return Color(hex: 0xFFFFFF)
        case .github:        return Color(hex: 0x58A6FF)
        case .hepburn:       return Color(hex: 0xD4A5A5)
        case .neon:          return Color(hex: 0xb347ff)
        case .neonSoft:      return Color(hex: 0xb347ff)
        case .neonPaint:     return Color(hex: 0xFF2D95)
        case .nous:          return Color(hex: 0x7C4DFF)
        case .poseidon:      return Color(hex: 0x4D9FFF)
        case .sienna:        return Color(hex: 0xC4875A)
        case .sisyphus:      return Color(hex: 0xB8860B)
        case .slate:         return Color(hex: 0x708090)
        case .verdigris:     return Color(hex: 0xC89A5A)
        case .zeus:          return Color(hex: 0xFFD700)
        }
    }

    /// Accent gradient for buttons and highlights.
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle divider / border.
    var divider: Color {
        foreground.opacity(0.1)
    }
}
