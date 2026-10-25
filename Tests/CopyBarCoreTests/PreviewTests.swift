@testable import CopyBarCore
import Foundation
import XCTest

final class PreviewTests: XCTestCase {
    func testVisiblePrefixSkipsLeadingInvisibleCharacters() {
        let text = String(repeating: "\u{200B} \n", count: 2000) + "hello\u{202E} world"
        XCTAssertEqual(Preview.visiblePrefix(text, maxLength: 1000), "hello world")
        XCTAssertEqual(Preview.visiblePrefix(text, maxLength: 5), "hello")
        XCTAssertEqual(Preview.visiblePrefix("one\n two", maxLength: 100), "one\n two")
        XCTAssertEqual(Preview.visiblePrefix(" \u{200B}\n", maxLength: 100), "")
    }

    func testHTMLTextDropsMarkup() {
        let html = """
            <meta charset="utf-8"><style>p { color: red; }</style><!-- note -->
            <b id="docs-internal-guid-1">Quarterly</b> <i>plan</i><p>Fish &amp; chips&nbsp;&#8212;&#x41;</p>
            <script>if (a < b) { x = "</p>" }</script><div>end</div>
            """
        XCTAssertEqual(Preview.htmlText(html, maxLength: 100), "Quarterly plan Fish & chips —A end")
    }

    func testHTMLTextSeparatesBlocksButNotInlineElements() {
        XCTAssertEqual(Preview.htmlText("<p>one</p><p>two<br/>three</p>", maxLength: 100), "one two three")
        XCTAssertEqual(Preview.htmlText("<b>He</b>llo", maxLength: 100), "Hello")
    }

    func testHTMLTextWithNoVisibleText() {
        XCTAssertEqual(Preview.htmlText("<meta charset='utf-8'><b id=\"x\"></b>", maxLength: 100), "")
        XCTAssertEqual(Preview.htmlText("<div>unclosed <span", maxLength: 100), "unclosed")
        XCTAssertEqual(Preview.htmlText("Tom &unknown; &#xZZ;", maxLength: 100), "Tom &unknown; &#xZZ;")
    }

    func testHTMLTextStopsAtMaxLength() {
        let html = "<p>" + String(repeating: "word ", count: 100_000) + "</p>"
        XCTAssertEqual(Preview.htmlText(html, maxLength: 9), "word word")
    }

    func testShortTextIsUnchanged() {
        XCTAssertEqual(Preview.line("hello", maxLength: 30), "hello")
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(Preview.line("  one\n\ttwo   three \n", maxLength: 30), "one two three")
    }

    func testLongTextIsTrimmedWithEllipsis() {
        let line = Preview.line(String(repeating: "a", count: 50), maxLength: 30)
        XCTAssertEqual(line.count, 30)
        XCTAssertTrue(line.hasSuffix("…"))
    }

    /// The original eager implementation, to check the lazy one against.
    private func eagerLine(_ text: String, maxLength: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(max(maxLength - 1, 0))) + "…"
    }

    func testLazyLineMatchesEagerLine() {
        let samples = [
            "", "   ", "a", "hello world", "  one\n\ttwo   three \n",
            "exactly ten", "abcdefghij", "abcdefghijk", "abcd efghij klm",
            "abcdefgh ij", "abcdefghi  j", "e\u{301}e\u{301} 👨‍👩‍👧 🇩🇪 x",
            "\r\n\r\nline one\r\nline two\r\n",
        ]
        for text in samples {
            for maxLength in [0, 1, 2, 5, 9, 10, 11, 30] {
                XCTAssertEqual(Preview.line(text, maxLength: maxLength),
                               eagerLine(text, maxLength: maxLength),
                               "text: \(text.debugDescription), maxLength: \(maxLength)")
            }
        }
    }

    func testHugeTextIsTrimmed() {
        let text = String(repeating: "word \n\t", count: 200_000)
        let line = Preview.line(text, maxLength: 12)
        XCTAssertEqual(line, "word word w…")
        XCTAssertEqual(line, eagerLine(text, maxLength: 12))
    }

    func testBidiControlsAreStripped() {
        // RLO ... PDF would show "txt.exe" reversed as "exe.txt".
        XCTAssertEqual(Preview.line("file\u{202E}txt.exe\u{202C}", maxLength: 30), "filetxt.exe")
        let bidi = "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}\u{200E}\u{200F}\u{061C}"
        XCTAssertEqual(Preview.line("a\(bidi)b", maxLength: 30), "ab")
    }

    func testFormatAndControlCharactersAreStripped() {
        XCTAssertEqual(Preview.line("pa\u{200B}ss\u{200C}wo\u{200D}rd\u{FEFF}\u{2060}", maxLength: 30), "password")
        XCTAssertEqual(Preview.line("a\u{0000}b\u{0007}c\u{001B}d\u{007F}e", maxLength: 30), "abcde")
        // Stripped characters don't count toward the length.
        XCTAssertEqual(Preview.line("\u{200B}\u{200B}\u{200B}abcde", maxLength: 5), "abcde")
        // Whitespace around invisible characters still collapses to one space.
        XCTAssertEqual(Preview.line("one \u{200B} \u{202E}\ttwo", maxLength: 30), "one two")
    }

    func testEmojiSequencesSurvive() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let rainbowFlag = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        for emoji in [family, rainbowFlag, scotland] {
            XCTAssertEqual(Preview.line("hi \(emoji)", maxLength: 30), "hi \(emoji)")
            XCTAssertEqual(Preview.sanitized(emoji), emoji)
        }
    }

    func testSanitizedKeepsNewlinesAndTabs() {
        XCTAssertEqual(Preview.sanitized("one\u{202E}\n\ttwo\u{200B}\r\nthree\u{0007}"), "one\n\ttwo\r\nthree")
        XCTAssertEqual(Preview.sanitized("plain text"), "plain text")
    }

    func testIsBlank() {
        XCTAssertTrue(Preview.isBlank(""))
        XCTAssertTrue(Preview.isBlank(" \n\t\r\n"))
        XCTAssertTrue(Preview.isBlank("\u{200B}\u{200D}\u{FEFF} \u{202E}\u{2066}\n\u{0000}"))
        XCTAssertFalse(Preview.isBlank("\u{200B}a"))
        XCTAssertFalse(Preview.isBlank(" . "))
    }

    func testSafeHTMLKeepsOnlyBareFormattingTags() {
        let html = """
            <meta charset="utf-8"><link rel="stylesheet" href="https://x.test/a.css">\
            <p style="background: url(https://x.test/b.png)" onclick="go()">Hello <img src="https://x.test/c.png">world</p>\
            <script src="https://x.test/d.js">alert(1)</script><iframe src="https://x.test/e">frame</iframe>\
            <table background="https://x.test/f.png"><tr><td class="c">cell</td></tr></table>\
            <style>@import "https://x.test/g.css";</style><strong>bold</strong> <a href="https://x.test/">link</a>
            """
        XCTAssertEqual(Preview.safeHTML(html),
                       "<p>Hello world</p><table><tr><td>cell</td></tr></table><b>bold</b> link")
    }

    func testSafeHTMLBlocksReviewPayloads() {
        let payloads = [
            "<body onload=\"fetch('https://x.test')\">a</body>",
            "<svg onload=\"fetch('https://x.test')\"><image href=\"https://x.test/a.png\"/></svg>b",
            "<div style=\"animation-name:x\" onanimationstart=\"go()\">c</div>",
            "<scr<img>ipt>alert(1)</scr<img>ipt>",
            "<img alt=\">\" src=\"https://x.test/t.png\">",
            "<img alt=\"<img\" title=\">\" src=\"https://x.test/t.png\">",
            "<div style=\"background: &#x75;rl(https://x.test/a.png)\">d</div>",
            "<style>@\\69mport 'https://x.test/a.css'</style>",
            "<meta http-equiv=\"refresh\" content=\"0;url=https://x.test\">",
            "<div title=\"a\"background=\"https://x.test/a.png\">e</div>",
            "<<script>script>alert(1)<</script>/script>",
        ]
        for payload in payloads {
            let safe = Preview.safeHTML(payload)
            XCTAssertFalse(safe.contains("x.test") && safe.contains("<img"), safe)
            XCTAssertNil(safe.range(of: "<[a-z]+[^>]*[ =\"']", options: .regularExpression), "attribute left in \(safe)")
            XCTAssertNil(safe.range(of: "<script", options: .caseInsensitive), safe)
            let tags = try! NSRegularExpression(pattern: "</?([a-z0-9]+)>")
            for match in tags.matches(in: safe, range: NSRange(safe.startIndex..., in: safe)) {
                let tag = (safe as NSString).substring(with: match.range(at: 1))
                XCTAssertTrue(["b", "i", "u", "s", "p", "div", "br"].contains(tag), "unexpected <\(tag)> in \(safe)")
            }
        }
        // `<scr<img>` is one tag named "scr", dropped; the rest is text.
        XCTAssertEqual(Preview.safeHTML("<scr<img>ipt>alert(1)</scr<img>ipt>"), "ipt&gt;alert(1)ipt&gt;")
    }

    func testSafeHTMLMapsInlineStyles() {
        // Google Docs wraps a copy in a <b> that isn't bold.
        let docs = "<b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><span style=\"font-weight:700;font-style:italic\">x</span>"
            + "<span style=\"text-decoration:underline line-through\">y</span></b>"
        XCTAssertEqual(Preview.safeHTML(docs), "<b><i>x</i></b><u><s>y</s></u>")
    }

    func testSafeHTMLEscapesTextAndClosesTags() {
        XCTAssertEqual(Preview.safeHTML("1 < 2 > 0 <b>unclosed <i>x"), "1 &lt; 2 &gt; 0 <b>unclosed <i>x</i></b>")
        XCTAssertEqual(Preview.safeHTML("<p>a<!-- <b> -->b<br/>c</p><script>never closed"), "<p>ab<br>c</p>")
    }

    func testHTMLTextSkipsInvisibleCharactersBeforeCounting() {
        let html = String(repeating: "&#8203;", count: 1000) + "hello"
        XCTAssertEqual(Preview.htmlText(html, maxLength: 1000), "hello")
        XCTAssertEqual(Preview.htmlText("one &#8203; two", maxLength: 100), "one two")
    }
}
