import SwiftUI

/// Sheet listing every model configured on the Hermes host, grouped by
/// provider. Selecting a model dispatches `/model <name>` through the chat
/// path (optionally with `--global` to persist beyond the current session).
struct ModelSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ModelStore.self) private var modelStore

    @State private var setAsGlobalDefault = false

    /// Called when the user picks a model. The bool is true when the change
    /// should persist globally (`/model <name> --global`).
    var onSelect: (ModelStore.HermesModel, Bool) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if modelStore.isLoading && modelStore.models.isEmpty {
                    ProgressView("Loading models…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if modelStore.models.isEmpty {
                    emptyState
                } else {
                    modelList
                }
            }
            .background(Design.Colors.background)
            .navigationTitle("Switch Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await modelStore.loadModels(force: true)
        }
    }

    private var modelList: some View {
        List {
            ForEach(modelStore.modelsByProvider, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.models) { model in
                        modelRow(model)
                    }
                }
            }

            Section {
                Toggle(isOn: $setAsGlobalDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set as default")
                            .font(Design.Typography.callout)
                        Text("Persist beyond the current session (--global)")
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    }
                }
                .tint(Design.Brand.accent)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func modelRow(_ model: ModelStore.HermesModel) -> some View {
        Button {
            modelStore.markActive(model)
            onSelect(model, setAsGlobalDefault)
            dismiss()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .foregroundStyle(Design.Colors.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let contextWindow = model.contextWindow {
                            Text("\(formatTokenCount(contextWindow)) context")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryForeground)
                        }
                        if model.isProviderDefault == true {
                            Text("provider default")
                                .font(Design.Typography.caption)
                                .foregroundStyle(Design.Colors.secondaryForeground)
                        }
                    }
                }

                Spacer()

                if modelStore.isActive(model) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.Brand.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "cpu")
                .font(.system(size: 32))
                .foregroundStyle(Design.Colors.secondaryForeground)
            Text(modelStore.errorMessage ?? "No models available")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)
            Text("Model list comes from the Hermes host — make sure it's online.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await modelStore.loadModels(force: true) }
            }
            .buttonStyle(.bordered)
        }
        .padding(Design.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
                .replacingOccurrences(of: ".0M", with: "M")
        } else if count >= 1_000 {
            return "\(count / 1_000)K"
        }
        return "\(count)"
    }
}
