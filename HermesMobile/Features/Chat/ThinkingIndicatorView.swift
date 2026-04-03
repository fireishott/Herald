import SwiftUI

struct ThinkingIndicatorView: View {
    let startTime: Date

    @State private var showElapsedTime = false
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            HermesAvatar(size: Design.Size.avatarSmall)
                .opacity(isPulsing ? 0.5 : 1.0)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                thinkingDots
                elapsedTimeLabel
            }

            Spacer(minLength: Design.Spacing.xxl)
        }
        .padding(.horizontal, Design.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture { showElapsedTime.toggle() }
        .onAppear {
            withAnimation(Design.Motion.breathe) {
                isPulsing = true
            }
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: Design.Spacing.xxs) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isPulsing
                    )
            }
        }
        .padding(.vertical, Design.Spacing.sm)
    }

    @ViewBuilder
    private var elapsedTimeLabel: some View {
        if showElapsedTime {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startTime)
                Text(formatElapsed(elapsed))
                    .font(Design.Typography.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
