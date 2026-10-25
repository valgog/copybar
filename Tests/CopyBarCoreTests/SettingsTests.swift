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

    func testIgnoredAppsMatchCaseInsensitively() {
        let settings = Settings.parse("ignored_apps = Com.Bitwarden.Desktop, com.apple.KeychainAccess").settings
        XCTAssertEqual(settings.ignoredApps, ["com.bitwarden.desktop", "com.apple.keychainaccess"])
        XCTAssertTrue(settings.isIgnoredApp("com.bitwarden.desktop"))
        XCTAssertTrue(settings.isIgnoredApp("COM.APPLE.KEYCHAINACCESS"))
        XCTAssertFalse(settings.isIgnoredApp("com.apple.TextEdit"))
    }

    func testHotkeyCanBeTurnedOff() {
        XCTAssertNil(Settings.parse("hotkey = none").settings.hotkey)
        XCTAssertNil(Settings.parse("hotkey =").settings.hotkey)
    }

    func testPreviewDelay() {
        XCTAssertEqual(Settings.parse("preview_delay = 0").settings.previewDelay, 0)
        XCTAssertEqual(Settings.parse("preview_delay = 1.25").settings.previewDelay, 1.25)
        XCTAssertNil(Settings.parse("preview_delay = off").settings.previewDelay)
        XCTAssertNil(Settings.parse("preview_delay =").settings.previewDelay)
        let (settings, warnings) = Settings.parse("preview_delay = 9")
        XCTAssertEqual(settings.previewDelay, Settings().previewDelay)
        XCTAssertEqual(warnings.count, 1)
    }
}
