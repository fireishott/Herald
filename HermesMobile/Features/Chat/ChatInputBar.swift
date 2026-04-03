import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onPenTap: () -> Void
    let onSlashCommand: (SlashCommand) -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSlashMode
    }

    private var isSlashMode: Bool {
        text.hasPrefix("/")
    }

    private var filteredCommands: [SlashCommand] {
        let query = String(text.dropFirst()).lowercased()
        if query.isEmpty { return SlashCommand.allCases }
        return SlashCommand.allCases.filter { $0.rawValue.hasPrefix(query) }
    }

    var body: some View {
        VStack(spacing: Design.Spacing.xs) {
            if isSlashMode && !filteredCommands.isEmpty {
                SlashCommandMenu(commands: filteredCommands) { command in
                    text = ""
                    onSlashCommand(command)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: Design.Spacing.xs) {
                penButton
                textField
                sendButton
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.md)
        }
        .animation(Design.Motion.quickResponse, value: isSlashMode)
    }

    private var penButton: some View {
        Button(action: onPenTap) {
            Image(systemName: "pencil")
                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: Design.Size.minTapTarget,
                    height: Design.Size.minTapTarget
                )
        }
        .accessibilityLabel("Attachments")
    }

    private var textField: some View {
        TextField("Message Hermes.", text: $text)
            .font(Design.Typography.body)
            .focused($isFocused)
            .onSubmit {
                if canSend { onSend() }
            }
    }

    private var sendButton: some View {
        Button {
            if canSend { onSend() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: Design.Size.iconLarge))
                .foregroundStyle(sendButtonColor)
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .animation(Design.Motion.quickResponse, value: canSend)
    }

    private var sendButtonColor: Color {
        canSend ? Design.Brand.accent : .gray.opacity(0.3)
    }
}
