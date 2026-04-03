import Foundation

enum SlashCommand: String, CaseIterable, Identifiable {
    case clear
    case status

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .clear: "/clear"
        case .status: "/status"
        }
    }

    var displayDescription: String {
        switch self {
        case .clear: "Archive conversation and start fresh"
        case .status: "Show connection and session info"
        }
    }

    var icon: String {
        switch self {
        case .clear: "trash"
        case .status: "info.circle"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .clear: true
        case .status: false
        }
    }
}
