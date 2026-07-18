import SwiftUI

/// Root view that adapts to device class:
/// - iPad: NavigationSplitView with sidebar + detail
/// - iPhone: existing MainTabView
struct AdaptiveRootView: View {
    @State private var selectedSection: SidebarSection = .chat

    var body: some View {
        if DeviceClass.isPad {
            iPadLayout
        } else {
            MainTabView()
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView {
            iPadSidebarView(selectedSection: $selectedSection)
        } detail: {
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .chat:
            NavigationStack {
                ChatScreen()
            }
        case .inbox:
            NavigationStack {
                InboxScreen()
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
}
