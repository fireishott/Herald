import SwiftUI

struct ChatScreen: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(TabRouter.self) private var router

    @State private var messageText = ""
    @State private var scrollPosition: ScrollPosition = .init(idType: UUID.self)
    @State private var showClearConfirmation = false
    @State private var showStatusCard = false

    private let thinkingIndicatorID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if hostStore.isHostOnline == false {
                    hostOfflineBanner
                }
                messageList
                ChatInputBar(
                    text: $messageText,
                    onSend: sendMessage,
                    onPenTap: openCapture,
                    onSlashCommand: handleSlashCommand
                )
            }
        }
        .navigationTitle("Hermes Agent")
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            chatStore.setPollingEnabled(true)
            await hostStore.refresh()
            await chatStore.loadConversationIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await hostStore.refresh()
            }
        }
        .onDisappear {
            chatStore.setPollingEnabled(false)
        }
        .onChange(of: chatStore.conversation?.messages.count ?? 0) {
            scrollToBottom()
        }
        .onChange(of: chatStore.pendingMessageSentAt) {
            scrollToBottom()
        }
        .confirmationDialog(
            "Clear Conversation",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await performClear() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will archive the current conversation and start a new session. This cannot be undone.")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: Design.Spacing.md) {
                if let messages = chatStore.conversation?.messages {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }

                if let sentAt = chatStore.pendingMessageSentAt {
                    ThinkingIndicatorView(startTime: sentAt)
                        .id(thinkingIndicatorID)
                        .transition(.opacity)
                }

                if showStatusCard {
                    StatusCardView(
                        isHostOnline: hostStore.isHostOnline,
                        messageCount: chatStore.conversation?.messages.count ?? 0,
                        conversationID: chatStore.conversation?.id,
                        dismissAction: { showStatusCard = false }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.vertical, Design.Spacing.md)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .redacted(reason: chatStore.isLoading ? .placeholder : [])
    }

    private var hostOfflineBanner: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text("Hermes host offline")
                    .font(Design.Typography.callout)
                Text("Messages will queue until your Hermes host reconnects.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                router.selectedTab = .settings
            }
            .buttonStyle(.glass)
            .font(Design.Typography.caption)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.md)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            StatusIndicator(status: hostStore.isHostOnline ? .connected : .disconnected)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        messageText = ""

        Task {
            await chatStore.sendMessage(content)
            scrollToBottom()
        }
    }

    private func openCapture() {
        router.navigate(to: .capture)
    }

    private func handleSlashCommand(_ command: SlashCommand) {
        switch command {
        case .clear:
            showClearConfirmation = true
        case .status:
            withAnimation(Design.Motion.standard) {
                showStatusCard.toggle()
            }
        }
    }

    private func performClear() async {
        do {
            try await chatStore.clearConversation()
            showStatusCard = false
        } catch {
            // Conversation unchanged on failure — user can retry
        }
    }

    private func scrollToBottom() {
        let targetID: UUID
        if chatStore.pendingMessageSentAt != nil {
            targetID = thinkingIndicatorID
        } else if let lastID = chatStore.conversation?.messages.last?.id {
            targetID = lastID
        } else {
            return
        }
        withAnimation(Design.Motion.standard) {
            scrollPosition.scrollTo(id: targetID, anchor: .bottom)
        }
    }
}
