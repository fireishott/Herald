import SwiftUI

struct PermissionsOnboardingScreen: View {
    @Environment(PairingStore.self) private var pairingStore
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        headerSection
                        permissionsList
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.lg)
                }

                continueButton
            }
        }
        .task {
            await permissionsStore.reloadCapabilities()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("002 · Access")
                .brandEyebrow()

            Text("PERMISSIONS")
                .font(Design.Typography.heroTitle)
                .tracking(-1.2)
                .foregroundStyle(Design.Colors.foreground)

            Text("enable only what you need. change anytime in settings.")
                .font(Design.Typography.editorialItalicSmall)
                .foregroundStyle(Design.Colors.foreground.opacity(0.85))
        }
    }

    // MARK: - Permissions List

    private var permissionsList: some View {
        VStack(spacing: Design.Spacing.sm) {
            ForEach(onboardingCapabilities) { capability in
                permissionRow(capability)
            }
        }
    }

    private var onboardingCapabilities: [DeviceCapability] {
        permissionsStore.capabilities.filter { capability in
            PermissionType.onboardingPermissions.contains(capability.permissionType)
        }
    }

    private func permissionRow(_ capability: DeviceCapability) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: capability.permissionType.displayIcon)
                .font(.system(size: Design.Size.iconMedium))
                .foregroundStyle(Design.Colors.foreground)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(Design.Colors.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .stroke(Design.Colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text(capability.permissionType.displayLabel)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)

                Text(capability.permissionType.explanation)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .lineLimit(2)

                if capability.status.isGranted {
                    Text("Granted")
                        .brandEyebrow(Design.Colors.success)
                }
            }

            Spacer()

            permissionAction(for: capability)
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .stroke(Design.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }

    @ViewBuilder
    private func permissionAction(for capability: DeviceCapability) -> some View {
        switch capability.status {
        case .notDetermined:
            Button {
                Task { await permissionsStore.requestPermission(for: capability.permissionType) }
            } label: {
                Text("Enable")
                    .brandEyebrow(Design.Colors.background)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
            }
            .background(Design.Brand.accent)
            .clipShape(Capsule())

        case .authorized, .authorizedWhenInUse, .authorizedAlways:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Design.Colors.success)

        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Settings")
                    .brandEyebrow(Design.Colors.warning)
            }

        case .limited, .restricted, .unsupported:
            Image(systemName: "minus.circle")
                .font(.system(size: 22))
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            pairingStore.completePermissionsOnboarding()
        } label: {
            Text("Continue →")
                .brandEyebrow(Design.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
        }
        .background(Design.Brand.accent)
        .clipShape(Capsule())
        .padding(.horizontal, Design.Spacing.md)
        .padding(.bottom, Design.Spacing.xl)
    }
}

// MARK: - PermissionStatus Helper

private extension PermissionStatus {
    var isGranted: Bool {
        switch self {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }
}
