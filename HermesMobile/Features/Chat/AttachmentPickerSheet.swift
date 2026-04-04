import SwiftUI

/// Bottom sheet for adding attachments to the chat — camera, photo library, or files.
struct AttachmentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        VStack(spacing: Design.Spacing.lg) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: Design.Size.iconMedium, weight: .medium))
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(width: Design.Size.glassCircleButton, height: Design.Size.glassCircleButton)
                        .background(Design.Colors.surface)
                        .clipShape(Circle())
                }

                Spacer()

                Text("Add to Chat")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)

                Spacer()

                // Invisible spacer to center title
                Color.clear
                    .frame(width: Design.Size.glassCircleButton, height: Design.Size.glassCircleButton)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.md)

            // Attachment options
            HStack(spacing: Design.Spacing.sm) {
                attachmentButton(
                    icon: "camera",
                    label: "Camera",
                    action: openCamera
                )

                attachmentButton(
                    icon: "photo.on.rectangle",
                    label: "Photos",
                    action: openPhotos
                )

                attachmentButton(
                    icon: "doc.badge.arrow.up",
                    label: "Files",
                    action: openFiles
                )
            }
            .padding(.horizontal, Design.Spacing.md)

            Spacer()
        }
        .background(Design.Colors.background)
    }

    private func attachmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: Design.Size.iconLarge))
                    .foregroundStyle(Design.Colors.foreground)
                Text(label)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.foreground)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        }
    }

    private func openCamera() {
        // Camera integration — future implementation
        dismiss()
    }

    private func openPhotos() {
        // Photo picker integration — future implementation
        dismiss()
    }

    private func openFiles() {
        // Document picker integration — future implementation
        dismiss()
    }
}
