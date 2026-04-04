import SwiftUI

/// Renders message content with inline markdown formatting and fenced code blocks.
///
/// Prose segments use native `AttributedString(markdown:)` for bold, italic,
/// inline code, links, and strikethrough. Fenced code blocks render with
/// `CodeBlockView` (monospaced font, background, copy button).
struct MarkdownContentView: View {
    let content: String
    let isStreaming: Bool
    var showCursor: Bool = false

    var body: some View {
        let segments = parseMarkdownSegments(content, isStreaming: isStreaming)

        if segments.isEmpty && showCursor {
            BlinkingCursor()
        } else {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    switch segment {
                    case .prose(_, let text):
                        proseView(text, isLast: index == segments.count - 1)
                    case .codeBlock(_, let language, let code):
                        CodeBlockView(language: language, code: code)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func proseView(_ text: String, isLast: Bool) -> some View {
        if showCursor && isLast {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                formattedText(text)
                BlinkingCursor()
            }
        } else {
            formattedText(text)
        }
    }

    private func formattedText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.foreground)
        } else {
            return Text(text)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.foreground)
        }
    }
}

// MARK: - Blinking Cursor

/// An animated text cursor that blinks at the end of streaming content.
struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("|")
            .font(Design.Typography.body)
            .foregroundStyle(Design.Brand.accent)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}
