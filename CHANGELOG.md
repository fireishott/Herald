# Changelog

All notable changes to Hermes iOS are documented here.

## [0.9.0] - 2026-07-17

### Added - iPad Layout Support

- **DeviceClass** (`Core/DeviceClass.swift`): enum detecting iPad vs iPhone at runtime via UIDevice.current.userInterfaceIdiom. Static current, isPad, isPhone properties (MainActor-isolated).

- **SidebarSection** (`Features/Sidebar/iPadSidebarView.swift`): enum with .chat, .inbox, .talk, .settings cases. Each has title and icon computed properties.

- **iPadSidebarView**: SwiftUI sidebar using List with .sidebar style. Shows section icons, titles, and an orange offline dot next to Chat when hostStore.connectionState != .online. Uses Design system tokens throughout.

- **AdaptiveRootView** (`Features/Sidebar/AdaptiveRootView.swift`): Root view that branches between NavigationSplitView (iPad, sidebar + detail) and MainTabView (iPhone, existing tab bar). Driven by DeviceClass.isPad.

- **TabRouter iPad extension** (`Core/Router.swift`): Added SidebarSection enum and oniPadSectionSwitch callback closure. When .settings is presented on iPad, calls the callback instead of presenting a sheet. All existing iPhone behavior unchanged.

### Changed

- **AppRootView**: Now renders AdaptiveRootView instead of MainTabView directly.
- **project.pbxproj**: New files registered in the main HermesMobile target Sources build phase.

### Architecture

iPad layout uses NavigationSplitView:

```
+--------------+----------------------------+
| Sidebar      | Detail                     |
| (list)       |                            |
|   Chat  <--  | ChatScreen / InboxScreen / |
|   Inbox      | TalkModeScreen /           |
|   Talk       | SettingsScreen             |
|   Settings   |                            |
+--------------+----------------------------+
```

iPhone layout unchanged: MainTabView with existing tab bar.

### Files Changed

| File | Status |
|------|--------|
| Core/DeviceClass.swift | New |
| Features/Sidebar/iPadSidebarView.swift | New |
| Features/Sidebar/AdaptiveRootView.swift | New |
| Core/Router.swift | Modified |
| Features/Onboarding/AppRootView.swift | Modified |
| HermesMobile.xcodeproj/project.pbxproj | Modified |
