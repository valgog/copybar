import AppKit
import ApplicationServices

/// Finds the text cursor of the focused app through the Accessibility API.
enum TextCaret {
    /// Whether CopyBar may use the Accessibility API. With `prompt`, macOS
    /// shows its "allow in System Settings" dialog if access is missing.
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Screen rectangle of the text cursor in Cocoa coordinates, or nil when
    /// the focused element isn't editable text or the app doesn't say.
    static func rect() -> NSRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        // Don't hang the hotkey on an app that is busy. A timeout set on the
        // system-wide element applies to every element.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        let app = AXUIElementCreateApplication(pid)

        guard let focused = element(app, kAXFocusedUIElementAttribute),
              let rangeValue = value(focused, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }

        if let rect = bounds(focused, range) { return rect }
        // Some apps give no bounds for an empty selection; use the right
        // edge of the character before the cursor instead.
        if range.length == 0, range.location > 0,
           let previous = bounds(focused, CFRange(location: range.location - 1, length: 1)) {
            return NSRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
        }
        return nil
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> NSRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success,
            let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.height > 0,
              rect.origin != .zero else { return nil }

        // Accessibility measures from the top-left of the main screen,
        // Cocoa from the bottom-left.
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let flipped = NSRect(x: rect.minX, y: mainScreen.frame.maxY - rect.maxY,
                             width: rect.width, height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(flipped.insetBy(dx: -1, dy: -1)) }) else {
            return nil
        }
        return flipped
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        return (result as! AXValue)
    }
}
