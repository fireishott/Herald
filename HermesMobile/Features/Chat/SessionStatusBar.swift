import SwiftUI

/// Desktop-style session status bar showing model, context usage, and session duration.
/// Placed persistently above the chat input bar.
struct SessionStatusBar: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(HermesHostStore.self) private var hostStore

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            // Model name
            if let model = chatStore.activeModelName ?? hostStore.currentHost?.hermesModel {
                Text(model)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Design.Brand.accent)
                    .lineLimit(1)
            } else {
                Text("--")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Text("|")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.divider)

            // Context usage
            if let used = chatStore.currentContextTokens,
               let maxCtx = chatStore.resolvedContextWindow(fallbackModelName: chatStore.activeModelName),
               maxCtx > 0 {
                let pct = Int(min(Double(used) / Double(maxCtx), 1.0) * 100)
                Text("\(formatK(used))/\(formatK(maxCtx)) \(pct)%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(pct > 85 ? .red : pct > 65 ? .orange : Design.Colors.secondaryForeground)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text("--/--")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }

            Text("|")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.divider)

            // Session duration (refreshes via id)
            if let startedAt = chatStore.sessionStartedAt {
                Text(formatDuration(Date().timeIntervalSince(startedAt)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .id("dur-\(Int(Date().timeIntervalSince1970 / 30))")
            }

            Spacer()

            // Connection indicator
            Circle()
                .fill(hostStore.connectionState == .online ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(hostStore.connectionState == .online ? "live" : "offline")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(hostStore.connectionState == .online ? Color.green : Color.orange)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, 6)
        .background(Design.Colors.surface.opacity(0.5))
        .overlay(alignment: .top) {
            Divider().background(Design.Colors.divider)
        }
    }

    private func formatK(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.0fk", Double(n)/1000) : "\(n)"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let rem = mins % 60
            return String(format: "%d:%02d:%02d", hrs, rem, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
