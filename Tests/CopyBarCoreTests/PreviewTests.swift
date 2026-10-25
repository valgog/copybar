@testable import CopyBarCore
import XCTest

final class PreviewTests: XCTestCase {
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
}
