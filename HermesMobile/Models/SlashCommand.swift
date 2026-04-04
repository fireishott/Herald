import Foundation

enum SlashCommand: String, CaseIterable, Identifiable {
    case new
    case reset
    case clear
    case history
    case save
    case retry
    case undo
    case title
    case compress
    case rollback
    case stop
    case background

    var id: String { rawValue }

    var displayTitle: String { "/\(rawValue)" }

    var displayDescription: String {
        switch self {
        case .new:        "Start a new session (fresh session ID + history)"
        case .reset:      "Start a new session (fresh session ID + history) (alias fo…"
        case .clear:      "Clear screen and start a new session"
        case .history:    "Show conversation history"
        case .save:       "Save the current conversation"
        case .retry:      "Retry the last message (resend to agent)"
        case .undo:       "Remove the last user/assistant exchange"
        case .title:      "Set a title for the current session (usage: /title [name])"
        case .compress:   "Manually compress conversation context"
        case .rollback:   "List or restore filesystem checkpoints (usage: /rollback […"
        case .stop:       "Kill all running background processes"
        case .background: "Run a prompt in the background (usage: /background <prompt>)"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .new, .reset, .clear, .undo: true
        default: false
        }
    }

    /// Whether this command accepts an inline argument after the command name.
    var acceptsArgument: Bool {
        switch self {
        case .title, .background: true
        default: false
        }
    }
}
