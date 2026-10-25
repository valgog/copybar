import Foundation

public enum Preview {
    /// Collapses whitespace (including newlines) into single spaces and
    /// trims the result to `maxLength` characters, ending with "…" when cut.
    public static func line(_ text: String, maxLength: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(max(maxLength - 1, 0))) + "…"
    }
}
