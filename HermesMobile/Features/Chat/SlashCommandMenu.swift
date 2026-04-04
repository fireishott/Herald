import SwiftUI

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { command in
                    Button { onSelect(command) } label: {
                        HStack(spacing: 0) {
                            Text(command.displayTitle)
                                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                                .foregroundStyle(Design.Brand.accent)
                                .frame(width: 90, alignment: .leading)

                            Text(command.displayDescription)
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryForeground)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, Design.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .padding(.horizontal, Design.Spacing.md)
    }
}
