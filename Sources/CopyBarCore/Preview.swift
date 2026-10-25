import Foundation

public enum Preview {
    /// Collapses whitespace (including newlines) into single spaces and
    /// trims the result to `maxLength` characters, ending with "…" when cut.
    /// Stops reading after `maxLength + 1` characters, so a huge copy costs
    /// no more than a short one.
    public static func line(_ text: String, maxLength: Int) -> String {
        let limit = max(maxLength, 0)
        var result = ""
        var count = 0
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                count += 1
                pendingSpace = false
            }
            result.append(character)
            count += 1
            if count > limit { break }
        }
        guard count > limit else { return result }
        return String(result.prefix(max(limit - 1, 0))) + "…"
    }
}
