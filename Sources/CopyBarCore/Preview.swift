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

    /// The first `maxLength` characters of `sanitized(text)`, starting at
    /// the first visible character. Stops reading once it has them, so it is
    /// cheap on a huge copy.
    public static func visiblePrefix(_ text: String, maxLength: Int) -> String {
        var result = ""
        var count = 0
        for character in text where count < maxLength {
            if result.isEmpty, character.isWhitespace { continue }
            let visible = visibleScalars(of: character)
            if visible.isEmpty { continue }
            result += visible
            count += 1
        }
        return result
    }

    /// `html` with everything removed that would make WebKit fetch
    /// something while rendering it: images, frames, embedded media,
    /// scripts, `<link>` and `<base>` elements, `src`-like attributes, and
    /// CSS `url(...)` and `@import`. Used before the hover preview renders
    /// copied HTML, so opening a preview never loads remote files (tracking
    /// pixels) or hangs the menu on a slow server. Regex based: good enough
    /// for a preview, not a security boundary for untrusted pages.
    public static func offlineHTML(_ html: String) -> String {
        var result = html
        for (pattern, template) in offlineRules {
            // Attribute removal works one attribute per match; repeat until stable.
            while true {
                let range = NSRange(result.startIndex..., in: result)
                let replaced = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: template)
                if replaced == result { break }
                result = replaced
            }
        }
        return result
    }

    private static let offlineRules: [(NSRegularExpression, String)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            // The patterns are constant, so a failure is a programming error.
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        }
        let fetching = "script|iframe|frame|object|embed|video|audio|picture|noscript"
        return [
            // Elements with fetching content, up to their end tag.
            (regex("<(\(fetching))\\b[^>]*>.*?</\\1\\s*>"), ""),
            // Single tags that fetch something, and openers left without an end tag.
            (regex("</?(?:\(fetching)|img|image|link|base|source|track|input|frameset)\\b[^>]*>"), ""),
            // Attributes that load a file, on any remaining element.
            (regex("(<[a-z][^>]*?)\\s(?:src|srcset|background|poster|data|lowsrc|dynsrc)\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)"), "$1"),
            (regex("url\\s*\\("), "blocked("),
            (regex("@import"), "@blocked"),
        ]
    }()

    /// The visible text of an HTML fragment, collapsed to single spaces and
    /// at most `maxLength` characters: tags and comments are dropped, and so
    /// is the content of `script`, `style`, `title` and `template`. Block
    /// elements and `<br>` become spaces. Only the common named entities
    /// and numeric ones are decoded. Good enough for a menu title, not a
    /// full HTML parser. Stops once it has `maxLength` characters.
    public static func htmlText(_ html: String, maxLength: Int) -> String {
        var result = ""
        var count = 0
        var pendingSpace = false
        func append(_ character: Character) {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                return
            }
            if pendingSpace {
                result.append(" ")
                count += 1
                pendingSpace = false
            }
            result.append(character)
            count += 1
        }

        let end = html.endIndex
        var index = html.startIndex
        while index < end, count < maxLength {
            let character = html[index]
            if character == "<" {
                if html[index...].hasPrefix("<!--") {
                    guard let close = html.range(of: "-->", range: index..<end) else { break }
                    index = close.upperBound
                    continue
                }
                guard let close = html[index...].firstIndex(of: ">") else { break }
                let tag = html[html.index(after: index)..<close]
                index = html.index(after: close)
                let name = tagName(tag)
                if hiddenElements.contains(name), !tag.hasSuffix("/") {
                    // Skip to the matching end tag; the content isn't markup.
                    guard let endTag = html.range(of: "</" + name, options: .caseInsensitive, range: index..<end),
                          let endClose = html[endTag.upperBound...].firstIndex(of: ">") else { break }
                    index = html.index(after: endClose)
                } else if blockElements.contains(name.hasPrefix("/") ? String(name.dropFirst()) : name) {
                    append(" ")
                }
                continue
            }
            if character == "&", let (decoded, next) = entity(in: html, at: index) {
                append(decoded)
                index = next
                continue
            }
            append(character)
            index = html.index(after: index)
        }
        return sanitized(result)
    }

    private static let hiddenElements: Set<String> = ["script", "style", "title", "template"]
    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt", "figcaption",
        "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main",
        "nav", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul",
    ]
    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    /// Lowercased name of the tag between `<` and `>`, with a leading `/`
    /// for an end tag.
    private static func tagName(_ tag: Substring) -> String {
        var name = ""
        for character in tag {
            if character == "/", name.isEmpty {
                name.append(character)
            } else if character.isLetter || character.isNumber {
                name.append(character)
            } else {
                break
            }
        }
        return name.lowercased()
    }

    /// The character for the entity starting with `&` at `index`, and the
    /// index after its `;`.
    private static func entity(in html: String, at index: String.Index) -> (Character, String.Index)? {
        let start = html.index(after: index)
        guard let semicolon = html[start...].prefix(10).firstIndex(of: ";") else { return nil }
        let body = html[start..<semicolon]
        let next = html.index(after: semicolon)
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return (Character(scalar), next)
        }
        guard let character = namedEntities[String(body)] else { return nil }
        return (character, next)
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
