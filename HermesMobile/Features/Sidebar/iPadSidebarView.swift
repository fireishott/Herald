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

struct iPadSidebarView: View {
    @Binding var selectedSection: SidebarSection
    @Environment(HermesHostStore.self) private var hostStore

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: section.icon)
                            .font(.system(size: Design.Size.iconSmall))
                            .foregroundStyle(selectedSection == section ? Design.Brand.accent : Design.Colors.secondaryForeground)
                            .frame(width: 24)
                        Text(section.title)
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.foreground)
                        Spacer()
                        if section == .chat && hostStore.connectionState != .online {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, Design.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selectedSection == section
                        ? Design.Brand.accent.opacity(0.12)
                        : Color.clear
                )
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Design.Colors.background)
        .navigationTitle("Hermes")
    }
}
