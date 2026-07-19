# Themes, Wallpaper, and Session History Design

## Overview

Add theming (6 presets matching Electron), chat background wallpaper, and session history improvements to the Hermes iOS app. The Electron desktop app already has a mature theming system with 6 presets (Nous, Midnight, Ember, Mono, Cyberpunk, Slate) — the iOS app will match these for a cohesive cross-platform experience.

**Scope decisions:**
- 6 theme presets matching Electron names and similar colors
- Light/Dark/System mode with auto-synthesized light variants for dark-only themes
- Chat background wallpaper (not full app background)
- Default wallpaper = Hermes logo silhouette (matching Electron)
- Built-in wallpaper presets + camera roll photo picker
- Full-text message search (relay change)
- Cross-device session visibility toggle (iOS change)
- CLI session sync/import deferred (separate feature)

---

## Section 1: Theme System

### Architecture

Theme state flows through the app via `@Observable ThemeManager` injected into the SwiftUI environment. `Design.Colors` and `Design.Brand.accent` become computed properties that read from the active theme, adapting to light/dark mode automatically.

### Theme Presets

Six presets matching the Electron app (`apps/desktop/src/themes/presets.ts`):

| Preset | Accent | Dark BG | Light BG | Notes |
|--------|--------|---------|----------|-------|
| **Nous** | Blue (#4A9EFF) | Deep blue-gray | Cool white | Default, glass-like |
| **Midnight** | Purple (#8B5CF6) | Deep blue-violet | Auto-synth | Dark only |
| **Ember** | Crimson (#EF4444) | Warm bronze | Auto-synth | Dark only |
| **Mono** | Gray (#A1A1AA) | Pure grayscale | Clean white | Minimal |
| **Cyberpunk** | Neon Green (#00FF41) | Black | Auto-synth | Dark only |
| **Slate** | Slate Blue (#64748B) | Cool slate | Auto-synth | Dark only |

Each preset defines:
- `accent: Color` — the theme's primary accent
- `darkColors: ThemePalette` — full dark mode palette (background, foreground, surface, secondaryForeground, divider)
- `lightColors: ThemePalette?` — explicit light palette (Nous, Mono) or nil (auto-synthesized)

### Light Mode Synthesis

For dark-only themes, light variants are auto-synthesized by inverting luminance (matching Electron's `synthLightColors()`):
- Background: dark background color with luminance inverted to 95%+
- Foreground: dark foreground with luminance inverted to 10%-
- Surface: light overlay on background
- Accent: unchanged

### New Files

- `HermesMobile/Core/Theme.swift` — `ThemePreset` enum, `ThemePalette` struct, preset definitions
- `HermesMobile/Core/ThemeManager.swift` — `@Observable`, loads/saves preference, provides current palette

### UserSettings Additions

```swift
enum ThemePreset: String, Codable, CaseIterable, Identifiable {
    case nous, midnight, ember, mono, cyberpunk, slate
}

enum ColorSchemePreference: String, Codable, CaseIterable {
    case system, light, dark
}
```

New properties in `UserSettings`:
- `themePreset: ThemePreset` (default: `.nous`)
- `colorSchemePreference: ColorSchemePreference` (default: `.system`)

### Design Token Adaptation

`Design.Colors` becomes computed properties reading from `ThemeManager`:

```swift
enum Colors {
    static var background: Color { ThemeManager.shared.current.background }
    static var foreground: Color { ThemeManager.shared.current.foreground }
    // etc.
}
```

### Settings UI

New "Appearance" section in `SettingsScreen`:
- Theme preset picker — 6 options with color swatch previews
- Light/Dark/System segmented control
- Chat Wallpaper picker (see Section 3)

---

## Section 2: Session History Improvements

### Full-Text Message Search (Relay)

**File:** `relay/app/services.py` — `search_sessions()` function

Current behavior: `ILIKE` search on `conversations.title` only.

New behavior: join `messages` table, search `messages.text` as well. Return sessions where either title or message content matches. Results ranked: title match first, then message match, most recent first.

```python
def search_sessions(user_id: str, query: str, device_id: str | None = None, limit: int = 50):
    # Join messages, search both title and message text
    # Distinct results, ordered by relevance
```

### Cross-Device Session Filter (iOS)

**File:** `HermesMobile/Stores/SessionListStore.swift`

New toggle: `showAllDevices: Bool` (default: false, persisted in UserSettings)

When enabled, `loadSessions()` does not pass `device_id` filter — shows all sessions regardless of source device (CLI, Telegram, other iOS devices, etc.).

UI: Toggle in the filter chip area next to All/Pinned/Archived.

### Session Source Indicators

Already partially implemented. Ensure all sources render correctly:
- iOS, CLI, Telegram, Discord, voice, cron, web
- Each with appropriate SF Symbol or custom icon

---

## Section 3: Wallpaper

### Wallpaper Types

```swift
enum ChatWallpaper: Codable, Equatable {
    case `default`          // Hermes logo silhouette
    case gradient1          // Abstract gradient presets
    case gradient2
    case gradient3
    case gradient4
    case texture1           // Subtle texture presets
    case texture2
    case solid              // Solid theme background color
    case custom(Data)       // User photo (JPEG data)
}
```

### Bundled Wallpapers

`HermesMobile/Resources/Wallpapers/`:
- `hermes-logo-silhouette.png` — default, centered logo watermark
- `gradient-1.png` through `gradient-4.png` — abstract gradients
- `texture-1.png`, `texture-2.png` — subtle textures

### Wallpaper Rendering

In `ChatScreen.swift`, behind the message list:

```swift
ZStack {
    // Wallpaper layer
    wallpaperImage
        .resizable()
        .aspectRatio(contentMode: .fill)
        .opacity(wallpaperOpacity)
        .overlay(Color.black.opacity(0.3)) // readability overlay
        .ignoresSafeArea()

    // Messages list
    messagesList
}
```

- `.default`: Hermes logo centered, 15% opacity, no fill/blur
- Gradients/textures: full bleed, 40% opacity
- `.custom`: full bleed, 40% opacity, slight Gaussian blur (radius 5)
- `.solid`: theme background color, no image

### Wallpaper Picker

`HermesMobile/Features/Settings/WallpaperPickerSheet.swift`:
- Grid of thumbnail previews (3 columns, 2 rows for presets)
- "Choose Photo" button opens SwiftUI `PhotosPicker`
- Tap preview → apply immediately
- Entry: Settings → Appearance → Chat Wallpaper

### UserSettings

```swift
var chatWallpaper: ChatWallpaper = .default
```

### Default

`.default` — Hermes logo silhouette matching the Electron app's default chat background.

---

## Implementation Order

1. **Theme system** — Theme.swift, ThemeManager.swift, adaptive Design tokens
2. **Theme Settings UI** — Appearance section in SettingsScreen
3. **Wallpaper rendering** — Chat background in ChatScreen
4. **Wallpaper picker** — Settings UI + PhotosPicker
5. **Session search improvement** — Relay full-text search
6. **Cross-device filter** — SessionListStore toggle + UI

## Key Patterns

- **iOS:** `@Observable` + SwiftUI environment injection (same as all stores)
- **Themes:** Match Electron preset names/colors for cross-platform consistency
- **Wallpaper:** Bundled assets + UserDefaults persistence + PhotosPicker
- **Session search:** Relay-side change only, no connector RPC needed
