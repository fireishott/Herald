import Foundation

@MainActor
@Observable
final class ChatStore {
    var conversation: Conversation?
    var isLoading = false
    var pendingMessageSentAt: Date?
    private var isPollingEnabled = false
    private var pollingTask: Task<Void, Never>?

    private let hermesClient: any HermesClientProtocol
    private let persistence: any AppPersistenceStoreProtocol

    init(hermesClient: any HermesClientProtocol, persistence: any AppPersistenceStoreProtocol) {
        self.hermesClient = hermesClient
        self.persistence = persistence
    }

    func loadConversationIfNeeded() async {
        if conversation == nil {
            conversation = persistence.loadConversationCache()
        }
        guard conversation == nil else { return }
        await loadConversation()
    }

    func loadConversation() async {
        isLoading = true
        defer { isLoading = false }
        conversation = await hermesClient.loadConversation()
        if let conversation {
            persistence.saveConversationCache(conversation)
        }
        restartPendingPollingIfNeeded()
    }

    func sendMessage(_ content: String) async {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        guard hasPendingDuplicateMessage(trimmedContent) == false else { return }

        let clientMessageID = UUID()
        let optimistic = Message(id: clientMessageID, sender: .user, content: trimmedContent, status: .sending)
        if conversation == nil {
            conversation = Conversation(title: "Hermes")
        }
        conversation?.messages.append(optimistic)
        conversation?.lastActivity = optimistic.timestamp
        pendingMessageSentAt = optimistic.timestamp

        let response = await hermesClient.send(message: trimmedContent, clientMessageID: clientMessageID)
        conversation = hermesClient.currentConversation

        if conversation == nil && response.status == .failed {
            conversation = Conversation(title: "Hermes")
            conversation?.messages.append(response)
            conversation?.lastActivity = response.timestamp
        }

        if !hasPendingMessages {
            pendingMessageSentAt = nil
        }

        if let conversation {
            persistence.saveConversationCache(conversation)
        }
        restartPendingPollingIfNeeded()
    }

    func clearConversation() async throws {
        let fresh = try await hermesClient.clearConversation()
        conversation = fresh
        pendingMessageSentAt = nil
        persistence.saveConversationCache(fresh)
        pollingTask?.cancel()
        pollingTask = nil
    }

    func setPollingEnabled(_ isEnabled: Bool) {
        isPollingEnabled = isEnabled
        if isEnabled {
            restartPendingPollingIfNeeded()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func reset() {
        pollingTask?.cancel()
        pollingTask = nil
        isPollingEnabled = false
        conversation = nil
        isLoading = false
        pendingMessageSentAt = nil
        persistence.clearConversationCache()
    }

    private var hasPendingMessages: Bool {
        conversation?.messages.contains(where: { $0.sender == .user && $0.status == .sending }) == true
    }

    private func hasPendingDuplicateMessage(_ content: String) -> Bool {
        conversation?.messages.contains(where: {
            $0.sender == .user
                && $0.status == .sending
                && $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == content
        }) == true
    }

    private func restartPendingPollingIfNeeded() {
        guard isPollingEnabled, hasPendingMessages else {
            pollingTask?.cancel()
            pollingTask = nil
            return
        }

        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self.conversation = await self.hermesClient.loadConversation()
                if let conversation = self.conversation {
                    self.persistence.saveConversationCache(conversation)
                }
                if self.hasPendingMessages == false {
                    self.pendingMessageSentAt = nil
                    break
                }
            }

            if self.pollingTask?.isCancelled == false {
                self.pollingTask = nil
            }
        }
    }
}
