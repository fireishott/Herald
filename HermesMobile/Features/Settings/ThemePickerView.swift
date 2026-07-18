import SwiftUI

// MARK: - Theme Picker
// Grid of all 21 themes with live color preview circles.
// Selecting a theme updates `settingsStore.settings.theme` which
// propagates through `SettingsStore` → persistence → `AppTheme.shared`.

struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: Design.Spacing.sm)
    ]

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            ScrollView {
                LazyVGrid(columns: columns, spacing: Design.Spacing.sm) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        themeCard(theme)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.md)
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Design.Brand.accent)
            }
        }
    }

    // MARK: - Theme Card

    @ViewBuilder
    private func themeCard(_ theme: AppTheme) -> some View {
        let isSelected = settingsStore.settings.theme == theme

        Button {
            withAnimation(Design.Motion.quickResponse) {
                settingsStore.settings.theme = theme
            }
        } label: {
            VStack(spacing: Design.Spacing.xs) {
                // Color preview: three overlapping circles
                ZStack {
                    Circle()
                        .fill(theme.background)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(theme.sidebar)
                        .frame(width: 32, height: 32)
                        .offset(x: -6, y: 6)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 20, height: 20)
                        .offset(x: 8, y: -4)
                }
                .frame(height: 52)

                Text(theme.displayName)
                    .font(Design.Typography.caption)
                    .foregroundStyle(isSelected ? theme.accent : Design.Colors.foreground)
                    .lineLimit(1)

                Text(theme.subtitle)
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .fill(isSelected ? theme.accent.opacity(0.12) : Design.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(
                        isSelected ? theme.accent : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", selected" : "")")
    }
}
