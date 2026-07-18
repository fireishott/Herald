import SwiftUI

/// A slide-out session browser drawer for iPhone.
/// Uses a drag gesture to reveal/hide from the leading edge.
struct iPhoneSessionDrawer: View {
    @Environment(SessionListStore.self) private var sessionStore
    @Environment(TabRouter.self) private var router
    @Binding var isOpen: Bool
    @State private var dragOffset: CGFloat = 0

    private let drawerWidth: CGFloat = min(UIScreen.main.bounds.width * 0.82, 340)

    var body: some View {
        ZStack(alignment: .leading) {
            // Backdrop
            if isOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
            }

            // Drawer content
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    drawerHeader
                    Divider()
                        .background(Design.Colors.divider)
                    sessionList
                }
                .frame(width: drawerWidth)
                .background(Design.Colors.background)
                .clipShape(
                    UnevenRoundedRectangle(
                        topTrailingRadius: Design.CornerRadius.lg,
                        bottomTrailingRadius: Design.CornerRadius.lg
                    )
                )

                Spacer()
            }
            .offset(x: isOpen ? min(0, dragOffset) : -drawerWidth + dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if isOpen {
                            // Only allow dragging closed (negative)
                            dragOffset = min(0, value.translation.width)
                        } else if value.translation.width > 10 {
                            // Allow peeking open from edge
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        let threshold = drawerWidth * 0.3
                        if isOpen {
                            if value.translation.width < -threshold {
                                close()
                            } else {
                                snapOpen()
                            }
                        } else {
                            if value.translation.width > threshold {
                                open()
                            } else {
                                snapClosed()
                            }
                        }
                    }
            )
            .animation(Design.Motion.standard, value: isOpen)
            .animation(.interactiveSpring, value: dragOffset)
        }
        .task {
            await sessionStore.loadSessions()
        }
    }

    // MARK: - Header

    private var drawerHeader: some View {
        HStack {
            Text("Sessions")
                .font(Design.Typography.screenTitle)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            Button {
                Task { await sessionStore.createNewSession() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(Design.Brand.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.md)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !sessionStore.pinnedSessions.isEmpty {
                    sectionHeader("PINNED")
                    ForEach(sessionStore.pinnedSessions) { session in
                        sessionRow(session, showPin: true)
                    }
                }

                if !sessionStore.recentSessions.isEmpty {
                    sectionHeader("RECENT")
                    ForEach(sessionStore.recentSessions.prefix(20)) { session in
                        sessionRow(session)
                    }
                }

                if sessionStore.pinnedSessions.isEmpty && sessionStore.recentSessions.isEmpty {
                    emptyState
                }

                if sessionStore.hasMore {
                    loadMoreButton
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.xs)
    }

    private func sessionRow(_ session: SessionSummary, showPin: Bool = false) -> some View {
        Button {
            close()
            Task { await sessionStore.switchToSession(session) }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: session.sourceIcon)
                    .font(.system(size: Design.Size.iconSmall))
                    .foregroundStyle(
                        sessionStore.activeSessionID == session.id
                            ? Design.Brand.accent
                            : Design.Colors.secondaryForeground
                    )
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.title)
                            .font(Design.Typography.body)
                            .foregroundStyle(
                                sessionStore.activeSessionID == session.id
                                    ? Design.Brand.accent
                                    : Design.Colors.foreground
                            )
                            .lineLimit(1)
                        if showPin {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Design.Brand.accent)
                                .rotationEffect(.degrees(45))
                        }
                    }
                    Text(session.previewText)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .lineLimit(1)
                }

                Spacer()

                Text(session.relativeTimeString)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            sessionStore.activeSessionID == session.id
                ? Design.Brand.accent.opacity(0.12)
                : Color.clear
        )
        .contextMenu {
            Button {
                Task { await sessionStore.togglePin(session) }
            } label: {
                Label(session.isPinned ? "Unpin" : "Pin",
                      systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            Button {
                Task { await sessionStore.archiveSession(session) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                Task { await sessionStore.deleteSession(session) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer().frame(height: 40)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.secondaryForeground)
            Text("No sessions yet")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
            Text("Start a new chat to create a session.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var loadMoreButton: some View {
        Button {
            Task { await sessionStore.loadMore() }
        } label: {
            HStack {
                Spacer()
                if sessionStore.isLoading {
                    ProgressView()
                        .tint(Design.Colors.secondaryForeground)
                } else {
                    Text("Load more")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Brand.accent)
                }
                Spacer()
            }
            .padding(.vertical, Design.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func open()   { setDrawer(open: true) }
    private func close()  { setDrawer(open: false) }
    private func snapOpen()   { withAnimation(Design.Motion.standard) { dragOffset = 0; isOpen = true } }
    private func snapClosed() { withAnimation(Design.Motion.standard) { dragOffset = 0; isOpen = false } }

    private func setDrawer(open: Bool) {
        withAnimation(Design.Motion.standard) {
            isOpen = open
            dragOffset = 0
        }
    }
}
