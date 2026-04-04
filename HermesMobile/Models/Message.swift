import Foundation

struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sender: MessageSender
    var content: String
    let timestamp: Date
    let jobID: UUID?
    var status: MessageStatus
    var toolActivity: String?
    var toolActivities: [ToolActivity]
    var codeDiff: CodeDiff?
    var isStreaming: Bool
    var voiceSessionDuration: TimeInterval?

    /// Whether this message was transcribed from a voice session.
    var isVoiceTranscript: Bool {
        sender == .voiceUser || sender == .voiceHermes
    }

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        content: String,
        timestamp: Date = .now,
        jobID: UUID? = nil,
        status: MessageStatus = .sent,
        toolActivity: String? = nil,
        toolActivities: [ToolActivity] = [],
        codeDiff: CodeDiff? = nil,
        isStreaming: Bool = false,
        voiceSessionDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.jobID = jobID
        self.status = status
        self.toolActivity = toolActivity
        self.toolActivities = toolActivities
        self.codeDiff = codeDiff
        self.isStreaming = isStreaming
        self.voiceSessionDuration = voiceSessionDuration
    }

    enum CodingKeys: String, CodingKey {
        case id, sender, content, timestamp, jobID, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sender = try container.decode(MessageSender.self, forKey: .sender)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        jobID = try container.decodeIfPresent(UUID.self, forKey: .jobID)
        status = try container.decode(MessageStatus.self, forKey: .status)
        toolActivity = nil
        toolActivities = []
        codeDiff = nil
        isStreaming = false
        voiceSessionDuration = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(status, forKey: .status)
    }
}
