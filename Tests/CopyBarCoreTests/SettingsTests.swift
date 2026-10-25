@testable import CopyBarCore
import XCTest

final class SettingsTests: XCTestCase {
    func testDefaultFileParsesToDefaults() {
        let (settings, warnings) = Settings.parse(Settings.defaultFileContents)
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(settings, Settings())
    }

    func testParsesValues() {
        let text = """
        # comment
        max_items = 10
        TEXT_LENGTH=40
          image_size = 64
        hotkey = ctrl+shift+c
        launch_at_login = no
        ignore_concealed = off
        ignored_apps = com.a.b,  com.c.d ,
        poll_interval = 1.5
        """
        let (settings, warnings) = Settings.parse(text)
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(settings.maxItems, 10)
        XCTAssertEqual(settings.textLength, 40)
        XCTAssertEqual(settings.imageSize, 64)
        XCTAssertEqual(settings.hotkey, "ctrl+shift+c")
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.ignoreConcealed)
        XCTAssertEqual(settings.ignoredApps, ["com.a.b", "com.c.d"])
        XCTAssertEqual(settings.pollInterval, 1.5)
    }

    func testBadValuesKeepDefaultsAndWarn() {
        let text = """
        max_items = lots
        image_size = 5000
        hotkey = v
        colour = blue
        just some words
        """
        let (settings, warnings) = Settings.parse(text)
        XCTAssertEqual(settings, Settings())
        XCTAssertEqual(warnings.count, 5)
    }

    func testHotkeyCanBeTurnedOff() {
        XCTAssertNil(Settings.parse("hotkey = none").settings.hotkey)
        XCTAssertNil(Settings.parse("hotkey =").settings.hotkey)
    }
}
