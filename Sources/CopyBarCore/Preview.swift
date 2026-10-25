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

    /// Copied HTML rebuilt for the hover preview, which renders it with
    /// `NSAttributedString`'s WebKit-based importer. Only text and a short
    /// list of structure and formatting tags survive, written afresh with no
    /// attributes, so the result can't run script or load anything: there
    /// are no event handlers, URLs or CSS, and no tag can be rebuilt from
    /// pieces because nothing is copied through except text, with `<` and
    /// `>` escaped. Bold, italic, underline and strike-through set with an
    /// inline `style` (as Google Docs does) become `<b>`, `<i>`, `<u>` and
    /// `<s>`, and text in a fixed-width font (inline `font-family`, `<tt>`,
    /// `<kbd>`, `<samp>`) becomes `<code>`. The contents of `script`,
    /// `style`, `svg` and similar elements are dropped. One linear pass.
    public static func safeHTML(_ html: String) -> String {
        let s = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        func emit(_ text: String) { output.append(contentsOf: text.unicodeScalars) }
        /// Open elements and the tags written for each, closed in reverse.
        var stack: [(name: String, written: [String])] = []
        func close(through index: Int) {
            while stack.count > index, let element = stack.popLast() {
                for tag in element.written.reversed() { emit("</\(tag)>") }
            }
        }

        var i = 0
        while i < s.count {
            let c = s[i]
            if c == ">" {
                emit("&gt;")
                i += 1
                continue
            }
            guard c == "<" else {
                output.append(c)
                i += 1
                continue
            }
            if hasPrefix(s, "<!--", at: i) {
                i = index(after: "-->", in: s, from: i + 4)
                continue
            }
            let next = i + 1
            if next < s.count, s[next] == "!" || s[next] == "?" {
                i = index(after: ">", in: s, from: next)
                continue
            }
            let closing = next < s.count && s[next] == "/"
            var k = closing ? next + 1 : next
            guard k < s.count, isASCIILetter(s[k]) else {
                emit("&lt;")
                i += 1
                continue
            }
            let nameStart = k
            while k < s.count, isASCIILetter(s[k]) || isASCIIDigit(s[k]) || s[k] == "-" || s[k] == ":" {
                k += 1
            }
            let name = String(String.UnicodeScalarView(s[nameStart..<k])).lowercased()
            // The tag ends at the first `>` outside a quoted attribute value.
            let attributesStart = k
            var quote: Unicode.Scalar?
            var afterEquals = false
            while k < s.count {
                let d = s[k]
                if let q = quote {
                    if d == q { quote = nil }
                } else if d == ">" {
                    break
                } else if afterEquals, d == "\"" || d == "'" {
                    quote = d
                }
                if quote == nil, !d.properties.isWhitespace { afterEquals = d == "=" }
                k += 1
            }
            let attributes = String(String.UnicodeScalarView(s[attributesStart..<k]))
            let selfClosing = attributes.hasSuffix("/")
            i = min(k + 1, s.count)

            if closing {
                if let index = stack.lastIndex(where: { $0.name == name }) { close(through: index) }
                continue
            }
            if hiddenContentElements.contains(name) {
                if !selfClosing { i = endOfElement(name, in: s, from: i) }
                continue
            }
            if name == "br" || name == "hr" {
                emit("<\(name)>")
                continue
            }
            // Deeper nesting is flattened, so finding an end tag stays cheap.
            guard !selfClosing, stack.count < 256 else { continue }
            var written = keptElements.contains(name) ? [name] : []
            var bold = ["b", "strong"].contains(name)
            var italic = ["i", "em"].contains(name)
            var underline = ["u", "ins"].contains(name)
            var strike = ["s", "strike", "del"].contains(name)
            var monospaced = ["tt", "kbd", "samp"].contains(name)
            if let style = attribute("style", in: attributes)?.lowercased()
                // Quotes around font names, decoded so `;` splits only declarations.
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#34;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'") {
                for declaration in style.split(separator: ";") {
                    let parts = declaration.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let property = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].replacingOccurrences(of: "!important", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    switch property {
                    case "font-weight":
                        if value == "bold" || value == "bolder" || (Int(value) ?? 0) >= 600 {
                            bold = true
                        } else if value == "normal" || value == "lighter" || Int(value) != nil {
                            bold = false
                        }
                    case "font-style":
                        italic = value == "italic" || value == "oblique"
                    case "text-decoration", "text-decoration-line":
                        underline = value.contains("underline")
                        strike = value.contains("line-through")
                    case "font-family":
                        if isMonospaced(fontFamily: value) { monospaced = true }
                    default:
                        break
                    }
                }
            }
            if bold { written.append("b") }
            if italic { written.append("i") }
            if underline { written.append("u") }
            if strike { written.append("s") }
            if monospaced, !written.contains("code") { written.append("code") }
            for tag in written { emit("<\(tag)>") }
            stack.append((name, written))
        }
        close(through: 0)
        return String(output)
    }

    /// Fonts whose names say they are fixed-width, as they appear in a
    /// lowercased CSS `font-family`. Only the first family counts: the rest
    /// are fallbacks.
    private static let monospacedFontNames = [
        "monospace", "mono", "courier", "menlo", "monaco", "consolas", "inconsolata",
        "fira code", "source code", "cascadia code", "lucida console",
    ]

    /// Whether a CSS `font-family` value names a fixed-width font first.
    static func isMonospaced(fontFamily: String) -> Bool {
        let first = fontFamily.split(separator: ",").first.map(String.init) ?? ""
        let name = first.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return !name.hasPrefix("monotype") && monospacedFontNames.contains { name.contains($0) }
    }

    /// Structure and formatting tags `safeHTML` writes as they are.
    private static let keptElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code",
        "table", "thead", "tbody", "tfoot", "tr", "td", "th", "sup", "sub",
    ]
    /// Elements whose content is not text to show.
    private static let hiddenContentElements: Set<String> = [
        "script", "style", "title", "template", "noscript", "svg", "math", "head", "iframe", "object",
        "textarea", "select", "xmp", "plaintext", "noembed", "noframes",
    ]

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    /// The scalar's value, lowercased if it is an ASCII capital letter.
    private static func asciiLowercased(_ scalar: Unicode.Scalar) -> UInt32 {
        (0x41...0x5A).contains(scalar.value) ? scalar.value + 0x20 : scalar.value
    }

    /// Whether `s` has `prefix` at `index`, ignoring ASCII case.
    private static func hasPrefix(_ s: [Unicode.Scalar], _ prefix: String, at index: Int) -> Bool {
        var offset = index
        for scalar in prefix.unicodeScalars {
            guard offset < s.count, asciiLowercased(s[offset]) == asciiLowercased(scalar) else { return false }
            offset += 1
        }
        return true
    }

    /// The index just past the next `needle` at or after `start`, or the end.
    private static func index(after needle: String, in s: [Unicode.Scalar], from start: Int) -> Int {
        let length = needle.unicodeScalars.count
        var i = start
        while i < s.count {
            if hasPrefix(s, needle, at: i) { return i + length }
            i += 1
        }
        return s.count
    }

    /// The index just past the end tag of `name`, or the end when there is none.
    private static func endOfElement(_ name: String, in s: [Unicode.Scalar], from start: Int) -> Int {
        var i = start
        while i < s.count {
            if s[i] == "<", hasPrefix(s, "</" + name, at: i) {
                let after = i + 2 + name.unicodeScalars.count
                if after >= s.count || !isASCIILetter(s[after]) {
                    return index(after: ">", in: s, from: after)
                }
            }
            i += 1
        }
        return s.count
    }

    /// The value of attribute `name` in a tag's attribute text, unquoted.
    private static func attribute(_ name: String, in attributes: String) -> String? {
        let s = Array(attributes.unicodeScalars)
        var i = 0
        func skipSpace() { while i < s.count, s[i].properties.isWhitespace || s[i] == "/" { i += 1 } }
        while i < s.count {
            skipSpace()
            let start = i
            while i < s.count, !s[i].properties.isWhitespace, s[i] != "=", s[i] != "/" { i += 1 }
            let attributeName = String(String.UnicodeScalarView(s[start..<i])).lowercased()
            while i < s.count, s[i].properties.isWhitespace { i += 1 }
            guard i < s.count, s[i] == "=" else {
                if i == start { i += 1 }
                continue
            }
            i += 1
            while i < s.count, s[i].properties.isWhitespace { i += 1 }
            var value = String.UnicodeScalarView()
            if i < s.count, s[i] == "\"" || s[i] == "'" {
                let quote = s[i]
                i += 1
                while i < s.count, s[i] != quote { value.append(s[i]); i += 1 }
                i += 1
            } else {
                while i < s.count, !s[i].properties.isWhitespace { value.append(s[i]); i += 1 }
            }
            if attributeName == name { return String(value) }
        }
        return nil
    }

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
            // Invisible characters don't count, so they can't use up maxLength.
            let visible = visibleScalars(of: character)
            if visible.isEmpty { return }
            if pendingSpace {
                result.append(" ")
                count += 1
                pendingSpace = false
            }
            result += visible
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
