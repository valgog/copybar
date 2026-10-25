@testable import CopyBarCore
import XCTest

final class GoogleClipTests: XCTestCase {
    /// Shaped like a real slide copy: the text commands (15) among layout ones.
    private let slide = #"""
        {"dih":1577552202,"data":"{\"unresolvedCommands\":[[12,\"g1\",0,0,[1,\"g0\",2,\"1_text + picture\"]],[3,\"g2\",108,[2.65,0,0,0.25,23887.9,8770.1],[54,15,55,0],\"g1\"],[15,\"g2\",null,0,\"WHAT IS NAKADI?\"],[17,\"g2\",null,15,16,[],[19,[null,1],21,\"Arial\"]],[15,\"g3\",null,0,\"Event Bus Broker\\u000bA distributed event bus.\"]]}"}
        """#
    private let slidesURL = "https://docs.google.com/presentation/d/1abc/edit#slide=id.g1"

    func testSlideCopy() {
        let entries = [
            (type: "application/x-vnd.google-docs-drawings-page+wrapped", value: slide),
            (type: "application/x-vnd.google-docs-internal-clip-id", value: "430fe0e2"),
        ]
        let description = GoogleClip.describe(entries: entries, sourceURL: slidesURL)
        XCTAssertEqual(description, GoogleClip.Description(
            label: "Google Slides slide", symbolName: "rectangle.on.rectangle",
            text: "WHAT IS NAKADI?\nEvent Bus Broker\nA distributed event bus."))
    }

    func testSlideCopyWithoutSourceURL() {
        let entries = [(type: "application/x-vnd.google-docs-drawings-page+wrapped", value: slide)]
        XCTAssertEqual(GoogleClip.describe(entries: entries, sourceURL: nil)?.label, "Google Slides slide")
    }

    func testOtherEditors() {
        let entries = [(type: "application/x-vnd.google-docs-image-clip+wrapped", value: "{}")]
        XCTAssertEqual(GoogleClip.describe(entries: entries,
                                           sourceURL: "https://docs.google.com/a/example.com/spreadsheets/d/1/edit"),
                       GoogleClip.Description(label: "Google Sheets content", symbolName: "tablecells", text: ""))
        XCTAssertEqual(GoogleClip.describe(entries: entries, sourceURL: "https://docs.google.com/document/d/1/edit")?.label,
                       "Google Docs content")
        XCTAssertEqual(GoogleClip.describe(entries: entries, sourceURL: slidesURL)?.label, "Google Slides content")
    }

    func testNotAGoogleCopy() {
        XCTAssertNil(GoogleClip.describe(entries: [(type: "text/x-custom", value: "x")], sourceURL: slidesURL))
        XCTAssertNil(GoogleClip.describe(entries: [], sourceURL: nil))
    }

    func testMalformedDrawingHasNoText() {
        let entries = [(type: "application/x-vnd.google-docs-drawings-page+wrapped", value: "not json")]
        XCTAssertEqual(GoogleClip.describe(entries: entries, sourceURL: slidesURL)?.text, "")
        XCTAssertEqual(GoogleClip.drawingText(#"{"data":"{\"unresolvedCommands\":[[15,\"g\"]]}"}"#), "")
    }
}
