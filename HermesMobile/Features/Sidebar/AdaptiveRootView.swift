import SwiftUI

/// Root view that adapts to device class:
/// - iPad: NavigationSplitView with sidebar + detail, right panel as overlay
/// - iPhone: NavigationStack with slide-out session drawer
struct AdaptiveRootView: View {
    @State private var selectedSection: SidebarSection = .chat
    @State private var isRightPanelOpen = false
    @State private var rightPanelTab: RightPanelTab = .logs

    var body: some View {
        if DeviceClass.isPad {
            iPadLayout
        } else {
            MainTabView()
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        ZStack(alignment: .trailing) {
            NavigationSplitView {
                iPadSidebarView(
                    selectedSection: $selectedSection,
                    isRightPanelOpen: $isRightPanelOpen
                )
            } detail: {
                detailContent
            }

            // Right-side inspector panel as overlay
            // This avoids wrapping NavigationSplitView in HStack,
            // which breaks sidebar auto-dismiss on compact iPad widths.
            if isRightPanelOpen {
                iPadRightPanelView(
                    isOpen: $isRightPanelOpen,
                    selectedTab: $rightPanelTab
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .animation(Design.Motion.standard, value: isRightPanelOpen)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .chat:
            NavigationStack {
                ChatScreen(isSessionDrawerOpen: .constant(false))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            rightPanelToggle
                        }
                    }
            }
        case .inbox:
            NavigationStack {
                InboxScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            rightPanelToggle
                        }
                    }
            }
        case .talk:
            NavigationStack {
                TalkModeScreen()
            }
        case .settings:
            NavigationStack {
                SettingsScreen()
            }
        }
    }

    private var rightPanelToggle: some View {
        Button {
            withAnimation(Design.Motion.standard) {
                isRightPanelOpen.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    isRightPanelOpen ? Design.Brand.accent : Design.Colors.secondaryForeground
                )
        }
        .buttonStyle(.plain)
    }
}
