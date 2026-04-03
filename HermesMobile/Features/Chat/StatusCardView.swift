import SwiftUI

struct StatusCardView: View {
    let isHostOnline: Bool
    let messageCount: Int
    let conversationID: UUID?
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Design.Brand.accent)
                Text("Session Status")
                    .font(Design.Typography.headline)
                Spacer()
                Button(action: dismissAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            statusRow("Connection", value: isHostOnline ? "Online" : "Offline")
            statusRow("Messages", value: "\(messageCount)")
            if let id = conversationID {
                statusRow("Session", value: String(id.uuidString.prefix(8)))
            }
        }
        .padding(Design.Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Design.Typography.callout)
        }
    }
}
