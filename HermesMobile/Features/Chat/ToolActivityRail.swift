import SwiftUI

/// A compact, expandable view showing the tools Hermes used during a response.
///
/// **Collapsed** (default): shows the latest/active tool label with a count badge.
/// **Expanded**: shows the full timeline of tool invocations.
struct ToolActivityRail: View {
    let activities: [ToolActivity]
    let isStreaming: Bool

    @State private var isExpanded = false

    private var latestActivity: ToolActivity? {
        activities.last(where: { $0.isActive }) ?? activities.last
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                compactHeader
                if isExpanded {
                    expandedTimeline
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Design.Motion.quickResponse, value: isExpanded)
            .animation(Design.Motion.quickResponse, value: activities.count)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tools: \(activities.map(\.label).joined(separator: ", "))")
        }
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        Button {
            guard activities.count > 1 || !isStreaming else { return }
            withAnimation(Design.Motion.quickResponse) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                if let latest = latestActivity {
                    if isStreaming && latest.isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Design.Colors.secondaryForeground)
                    }

                    Text(latest.label)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                if activities.count > 1 {
                    Text("\(activities.count)")
                        .font(Design.Typography.caption2.weight(.medium))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                        .padding(.horizontal, Design.Spacing.xxs + 2)
                        .padding(.vertical, Design.Spacing.xxxs)
                        .background {
                            Capsule().fill(Design.Colors.surface)
                        }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xxs + 1)
            .background(Design.Colors.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Timeline

    private var expandedTimeline: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
            ForEach(activities) { activity in
                HStack(spacing: Design.Spacing.xs) {
                    Circle()
                        .fill(activity.isActive ? Design.Brand.accent : Design.Colors.secondaryForeground)
                        .frame(width: 5, height: 5)

                    Text(activity.label)
                        .font(Design.Typography.caption)
                        .foregroundStyle(activity.isActive ? Design.Colors.foreground : Design.Colors.secondaryForeground)
                        .lineLimit(1)

                    Spacer()

                    if !activity.isActive {
                        Text(activity.startedAt, style: .time)
                            .font(Design.Typography.caption2)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    } else if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Design.Colors.secondaryForeground)
                    }
                }
                .padding(.horizontal, Design.Spacing.xs)
                .padding(.vertical, Design.Spacing.xxxs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Design.Spacing.xxs)
        .padding(.horizontal, Design.Spacing.xxs)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
    }
}
