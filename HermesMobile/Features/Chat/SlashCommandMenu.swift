import SwiftUI

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(commands) { command in
                Button { onSelect(command) } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: command.icon)
                            .frame(width: Design.Size.iconMedium)

                        VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                            Text(command.displayTitle)
                                .font(Design.Typography.headline)
                            Text(command.displayDescription)
                                .font(Design.Typography.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                }
                .foregroundStyle(command.isDestructive ? .red : .primary)

                if command.id != commands.last?.id {
                    Divider()
                        .padding(.leading, Design.Spacing.xxl)
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
    }
}
