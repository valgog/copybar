@testable import CopyBarCore
import XCTest

final class HotKeySpecTests: XCTestCase {
    func testParsesModifiersAndKey() {
        XCTAssertEqual(HotKeySpec.parse("cmd+alt+v"), HotKeySpec(keyCode: 9, modifiers: [.command, .option]))
        XCTAssertEqual(HotKeySpec.parse("Ctrl + Shift + Space"), HotKeySpec(keyCode: 49, modifiers: [.control, .shift]))
        XCTAssertEqual(HotKeySpec.parse("⌘⇧"), nil)
    }

    func testRejectsInvalidShortcuts() {
        XCTAssertNil(HotKeySpec.parse("v"))             // no modifier
        XCTAssertNil(HotKeySpec.parse("cmd+alt"))       // no key
        XCTAssertNil(HotKeySpec.parse("cmd+v+c"))       // two keys
        XCTAssertNil(HotKeySpec.parse("cmd+f13"))       // unknown key
    }
}
