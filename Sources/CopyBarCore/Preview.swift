import Foundation

public enum Preview {
    /// Collapses whitespace (including newlines) into single spaces, drops
    /// invisible characters (see `sanitized`) and trims the result to
    /// `maxLength` characters, ending with "…" when cut. Stops reading after
    /// `maxLength + 1` characters, so a huge copy costs no more than a short
    /// one.
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
            let visible = visibleScalars(of: character)
            if visible.isEmpty { continue }
            if pendingSpace {
                result.append(" ")
                count += 1
                pendingSpace = false
            }
            result += visible
            count += visible.count
            if count > limit {
                // Pieces left after stripping can merge into one character.
                count = result.count
                if count > limit { break }
            }
        }
        guard count > limit else { return result }
        return String(result.prefix(max(limit - 1, 0))) + "…"
    }

    /// `text` without invisible characters that could disguise what it
    /// shows: bidi controls (which can reorder text, e.g. a "harmless"
    /// command), zero-width and other format characters, and control
    /// characters other than whitespace. Newlines and tabs are kept.
    public static func sanitized(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isInvisible) else { return text }
        var result = ""
        for character in text {
            result += visibleScalars(of: character)
        }
        return result
    }

    /// Whether `text` has nothing visible: only whitespace and the
    /// invisible characters that `sanitized` removes. Such copies aren't
    /// worth saving.
    public static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.properties.isWhitespace || isInvisible($0) }
    }

    /// Format (Cf) characters, which include the bidi controls and zero-width
    /// characters, and control (Cc) characters that aren't whitespace.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .format: return true
        case .control: return !scalar.properties.isWhitespace
        default: return false
        }
    }

    /// `character` without its invisible scalars. A zero-width joiner inside
    /// an emoji sequence (family, rainbow flag) and tag characters inside a
    /// subdivision flag (Scotland) are kept so those still render as one
    /// emoji.
    private static func visibleScalars(of character: Character) -> String {
        let scalars = Array(character.unicodeScalars)
        guard scalars.contains(where: isInvisible) else { return String(character) }
        var kept = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated()
        where !isInvisible(scalar) || isPartOfEmoji(scalars, at: index) {
            kept.append(scalar)
        }
        return String(kept)
    }

    private static func isPartOfEmoji(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let value = scalars[index].value
        if value == 0x200D {
            // Joins two emoji, possibly after a U+FE0F variation selector.
            guard index + 1 < scalars.count, scalars[index + 1].properties.isEmoji else { return false }
            var before = index - 1
            while before >= 0, scalars[before].value == 0xFE0F { before -= 1 }
            return before >= 0 && scalars[before].properties.isEmoji
        }
        if (0xE0020...0xE007F).contains(value) {
            // Tag sequences follow U+1F3F4 WAVING BLACK FLAG.
            return scalars.first?.value == 0x1F3F4
        }
        return false
    }
}
