import SwiftUI

/// Right-side inspector panel for iPad.
/// Shows Hermes engine logs, terminal output, and tool activity —
/// similar to the right panel in Hermes Desktop.
struct iPadRightPanelView: View {
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(ChatStore.self) private var chatStore
    @Binding var isOpen: Bool
    @Binding var selectedTab: RightPanelTab

    var body: some View {
        if !isOpen { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 0) {
                tabBar

                switch selectedTab {
                case .logs:     logsContent
                case .terminal: terminalContent
                case .tools:    toolsContent
                }
            }
            .frame(width: panelWidth)
            .background(Design.Colors.surface)
        )
    }

    private let panelWidth: CGFloat = 300

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RightPanelTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Design.Brand.accent : Design.Colors.secondaryForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing.sm)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(Design.Motion.standard) { isOpen = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .padding(.horizontal, Design.Spacing.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Design.Spacing.xs)
        .background(Design.Colors.background)
    }

    // MARK: - Logs

    private var logsContent: some View {
        VStack(spacing: 0) {
            logFilterBar

            if chatStore.logEntries.isEmpty {
                emptyState(icon: "terminal", message: "No log entries yet",
                           detail: "Logs appear here when Hermes processes messages, runs tools, or executes commands.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chatStore.logEntries.enumerated()), id: \.offset) { idx, entry in
                            logEntryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private var logFilterBar: some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                Text(level.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(level.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(level.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
            Button { chatStore.logEntries.removeAll() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .overlay(alignment: .bottom) {
            Divider().background(Design.Colors.divider)
        }
    }

    private func logEntryRow(_ entry: (timestamp: Date, level: String, message: String)) -> some View {
        let color = logLevelColor(entry.level)
        let isLast = entry.timestamp == chatStore.logEntries.last?.timestamp
            && entry.message == chatStore.logEntries.last?.message
        return HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, style: .time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.6))
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 4)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, 3)
        .background(isLast ? Design.Brand.accent.opacity(0.06) : Color.clear)
    }

    private func logLevelColor(_ level: String) -> Color {
        switch level.uppercased() {
        case "WARN": return .orange
        case "ERR", "ERROR": return .red
        case "DBG", "DEBUG": return Design.Colors.secondaryForeground
        case "TOOL": return Design.Brand.accent
        default: return Design.Colors.foreground
        }
    }

    // MARK: - Terminal

    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(.red).frame(width: 8, height: 8)
                Circle().fill(.yellow).frame(width: 8, height: 8)
                Circle().fill(.green).frame(width: 8, height: 8)
                Spacer()
                Text("hermes — bash")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.sm).padding(.vertical, 6)
            .background(Color.black.opacity(0.25))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("$ hermes agent --version")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.green)
                    Text("Hermes Agent v2.1.0 — Nous Research")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Design.Colors.foreground)
                    Text("")
                    Text("$ tail -f ~/.hermes/logs/agent.log")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.green)
                    Text("Connected to relay · Host: \(hostStore.currentHost?.displayName ?? "unknown")")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Design.Colors.foreground)
                    Text("")
                    Text("Terminal integration coming soon.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.6))
                    Spacer()
                }
                .padding(Design.Spacing.sm)
                .textSelection(.enabled)
            }
        }
        .background(Design.Colors.background)
    }

    // MARK: - Tools

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOOL ACTIVITY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryForeground)
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.vertical, Design.Spacing.xs)
            Divider().background(Design.Colors.divider)

            if let startedAt = chatStore.sessionStartedAt {
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    Text("SESSION").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                    usageRow("Duration", value: formatDuration(Date().timeIntervalSince(startedAt)))
                    if let model = chatStore.activeModelName {
                        usageRow("Model", value: model)
                    }
                    if let ctx = chatStore.contextWindow {
                        usageRow("Context Window", value: formatTokenCount(ctx))
                    }
                }
                .padding(Design.Spacing.sm)
                Divider().background(Design.Colors.divider).padding(.horizontal, Design.Spacing.sm)
            }
            if chatStore.conversation?.latestUsage == nil {
                emptyState(icon: "hammer", message: "No tool activity yet",
                           detail: "Tool calls and execution results from the Hermes agent appear here.")
            } else if let usage = chatStore.conversation?.latestUsage {
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    usageRow("Prompt tokens", value: usage.promptTokens)
                    usageRow("Completion tokens", value: usage.completionTokens)
                    usageRow("Total tokens", value: usage.totalTokens)
                }
                .padding(Design.Spacing.sm)
            }
        }
    }

        private func usageRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Design.Colors.secondaryForeground)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.Colors.foreground)
        }
    }

    private func usageRow(_ label: String, value: Int?) -> some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Design.Colors.secondaryForeground)
            Spacer()
            Text(value.map { "\($0)" } ?? "--")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.Colors.foreground)
        }
    }

    private func emptyState(icon: String, message: String, detail: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.5))
            Text(message)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
            Text(detail)
                .font(Design.Typography.caption2)
                .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.lg)
            Spacer()
        }
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

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Right Panel Tab

enum RightPanelTab: String, CaseIterable, Identifiable {
    case logs, terminal, tools
    var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: "Logs"
        case .terminal: "Term"
        case .tools: "Tools"
        }
    }

    var icon: String {
        switch self {
        case .logs: "list.bullet.rectangle"
        case .terminal: "apple.terminal"
        case .tools: "hammer"
        }
    }
}

// MARK: - Log Entry

enum LogLevel: String, CaseIterable {
    case info, warn, error, debug, tool

    var label: String {
        switch self {
        case .info:  "INFO"
        case .warn:  "WARN"
        case .error: "ERR"
        case .debug: "DBG"
        case .tool:  "TOOL"
        }
    }

    var color: Color {
        switch self {
        case .info:  Design.Colors.foreground
        case .warn:  .orange
        case .error: .red
        case .debug: Design.Colors.secondaryForeground
        case .tool:  Design.Brand.accent
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: LogLevel
    let message: String
}
