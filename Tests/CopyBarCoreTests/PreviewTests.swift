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
}
