import SwiftUI

/// Root view that adapts to device class:
/// - iPad: NavigationSplitView with sidebar + detail
/// - iPhone: existing MainTabView
struct AdaptiveRootView: View {
    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @State private var selectedSection: SidebarSection = .chat
    
    var body: some View {
        if DeviceClass.isPad {
            iPadLayout
        } else {
            MainTabView()
        }
    }
    
    // MARK: - iPad Layout (NousResearch-style three-panel)
    
    private var iPadLayout: some View {
        NavigationSplitView {
            iPadSidebarView(selectedSection: )
        } detail: {
            detailContent
        }
        .onChange(of: selectedSection) { _, _ in
            // Reset navigation when switching sections
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
