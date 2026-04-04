import Foundation

/// A segment of parsed markdown content — either prose (inline markdown) or a fenced code block.
enum MarkdownSegment: Identifiable {
    case prose(id: UUID = UUID(), text: String)
    case codeBlock(id: UUID = UUID(), language: String?, code: String)

    var id: UUID {
        switch self {
        case .prose(let id, _): return id
        case .codeBlock(let id, _, _): return id
        }
    }
}

/// Parses markdown content into alternating prose and fenced code block segments.
///
/// Prose segments retain inline markdown (`**bold**`, `` `code` ``, `[links]()`, etc.)
/// that `AttributedString(markdown:)` handles natively.
///
/// During streaming, an unclosed fence at the end of content is still emitted as a
/// `.codeBlock` so the user sees code as it arrives.
func parseMarkdownSegments(_ content: String, isStreaming: Bool = false) -> [MarkdownSegment] {
    guard !content.isEmpty else { return [] }

    let lines = content.components(separatedBy: "\n")
    var segments: [MarkdownSegment] = []
    var currentProse: [String] = []
    var currentCode: [String] = []
    var codeLanguage: String?
    var insideCodeBlock = false

    for line in lines {
        if !insideCodeBlock {
            if line.hasPrefix("```") {
                // Flush accumulated prose
                if !currentProse.isEmpty {
                    let text = currentProse.joined(separator: "\n")
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.prose(text: text))
                    }
                    currentProse = []
                }
                // Start a code block
                insideCodeBlock = true
                let langTag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = langTag.isEmpty ? nil : langTag
                currentCode = []
            } else {
                currentProse.append(line)
            }
        } else {
            if line.hasPrefix("```") {
                // Close the code block
                insideCodeBlock = false
                let code = currentCode.joined(separator: "\n")
                segments.append(.codeBlock(language: codeLanguage, code: code))
                currentCode = []
                codeLanguage = nil
            } else {
                currentCode.append(line)
            }
        }
    }

    // Flush remaining content
    if insideCodeBlock {
        // Unclosed code block — emit it if streaming (user sees code as it arrives)
        // or if there's content (tolerant rendering)
        let code = currentCode.joined(separator: "\n")
        if isStreaming || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.codeBlock(language: codeLanguage, code: code))
        } else {
            // If not streaming and empty, treat the opening fence as prose
            currentProse.append("```\(codeLanguage ?? "")")
            currentProse.append(contentsOf: currentCode)
            let text = currentProse.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.prose(text: text))
            }
        }
    } else if !currentProse.isEmpty {
        let text = currentProse.joined(separator: "\n")
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.prose(text: text))
        }
    }

    return segments
}
