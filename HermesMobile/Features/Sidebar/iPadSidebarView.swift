import SwiftUI

// MARK: - Sidebar Section

/// Sections available in the iPad sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case chat
    case inbox
    case talk
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:     "Chat"
        case .inbox:    "Inbox"
        case .talk:     "Talk"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chat:     "bubble.left.and.bubble.right"
        case .inbox:    "tray"
        case .talk:     "waveform"
        case .settings: "gearshape"
        }
    }
}

// MARK: - iPad Sidebar View

/// Sidebar navigation used on iPad as the primary content switcher.
/// Selecting a section updates the router; the detail pane observes the
/// router's `selectedTab` to show the matching screen.
struct iPadSidebarView: View {
    @Environment(TabRouter.self) private var router
    @Environment(HermesHostStore.self) private var hostStore

    var body: some View {
        @Bindable var router = router

        List(SidebarSection.allCases, selection: $router.selectedTab) { section in
            sidebarRow(for: section)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Design.Colors.background)
        .navigationTitle("Hermes")
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func sidebarRow(for section: SidebarSection) -> some View {
        Label {
            HStack(spacing: Design.Spacing.xs) {
                Text(section.title)
                    .font(Design.Typography.body)

                // Show a warning dot next to Chat when the host is offline
                if section == .chat && hostStore.connectionState != .online {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Host offline")
                }
            }
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: Design.Size.iconSmall))
                .foregroundStyle(Design.Colors.foreground)
        }
        .tag(section)
    }
}
