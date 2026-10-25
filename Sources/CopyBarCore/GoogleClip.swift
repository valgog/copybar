import Foundation

/// Describes a copy made in Google Docs, Sheets, Slides or Drawings in
/// Chrome. A slide copy has no usable plain text or HTML: its content is in
/// Google's own formats inside `org.chromium.web-custom-data` (see
/// `WebCustomData`), and `org.chromium.source-url` names the page.
public enum GoogleClip {
    public struct Description: Equatable {
        /// What the copy is, e.g. "Google Slides slide".
        public let label: String
        /// SF Symbol name for the menu entry.
        public let symbolName: String
        /// Text found in the copy, or "" if none.
        public let text: String
    }

    /// A slide or a Google Drawings page: `{"dih": …, "data": "<JSON>"}`
    /// where the inner JSON holds `unresolvedCommands`.
    static let drawingPageType = "application/x-vnd.google-docs-drawings-page+wrapped"
    private static let typePrefix = "application/x-vnd.google-docs-"
    /// The command that inserts text into a shape: `[15, shapeID, _, index, text]`.
    private static let insertTextCommand = 15

    /// Nil when the copy has no Google editor formats.
    public static func describe(entries: [(type: String, value: String)], sourceURL: String?) -> Description? {
        guard entries.contains(where: { $0.type.hasPrefix(typePrefix) }) else { return nil }
        let drawingPage = entries.first { $0.type == drawingPageType }?.value
        // Slides copies whole slides as drawing pages; it's the likely editor
        // when Chrome doesn't say.
        let editor = sourceURL.flatMap(editor(of:)) ?? (drawingPage != nil ? .slides : .docs)
        let label = editor == .slides && drawingPage != nil ? "Google Slides slide" : "\(editor.rawValue) content"
        return Description(label: label, symbolName: editor.symbolName,
                           text: drawingPage.flatMap(drawingText) ?? "")
    }

    enum Editor: String {
        case docs = "Google Docs", sheets = "Google Sheets", slides = "Google Slides", drawings = "Google Drawings"

        var symbolName: String {
            switch self {
            case .docs: return "doc.text"
            case .sheets: return "tablecells"
            case .slides: return "rectangle.on.rectangle"
            case .drawings: return "scribble"
            }
        }
    }

    /// The editor from a docs.google.com URL. Workspace accounts may have
    /// `/a/<domain>/` before the editor's path.
    static func editor(of sourceURL: String) -> Editor? {
        guard let url = URL(string: sourceURL), url.host == "docs.google.com" else { return nil }
        for component in url.pathComponents {
            switch component {
            case "document": return .docs
            case "spreadsheets": return .sheets
            case "presentation": return .slides
            case "drawings": return .drawings
            default: continue
            }
        }
        return nil
    }

    /// The text of the shapes on a copied slide or drawing, one shape per
    /// line, in the order they were inserted.
    static func drawingText(_ wrapped: String) -> String? {
        guard let outer = try? JSONSerialization.jsonObject(with: Data(wrapped.utf8)) as? [String: Any],
              let inner = outer["data"] as? String,
              let data = try? JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: Any],
              let commands = data["unresolvedCommands"] as? [Any] else { return nil }
        var pieces: [String] = []
        for case let command as [Any] in commands {
            guard command.count > 4, command[0] as? Int == insertTextCommand,
                  let text = command[4] as? String else { continue }
            // Slides uses a vertical tab for a line break inside a paragraph.
            pieces.append(text.replacingOccurrences(of: "\u{0B}", with: "\n"))
        }
        return pieces.joined(separator: "\n")
    }
}
