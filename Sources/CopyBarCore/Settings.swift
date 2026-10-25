import Foundation

/// User settings, read from a simple `key = value` file.
public struct Settings: Equatable {
    public var maxItems = 50
    public var textLength = 30
    public var imageSize = 50
    public var pollInterval = 0.5
    public var hotkey: String? = "cmd+alt+v"
    public var launchAtLogin = true
    public var ignoreConcealed = true
    public var ignoredApps: [String] = []

    public init() {}

    /// Parses the config file text. Unknown keys and bad values are reported
    /// as warnings and leave the default in place.
    public static func parse(_ text: String) -> (settings: Settings, warnings: [String]) {
        var settings = Settings()
        var warnings: [String] = []

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            let lineNo = index + 1
            guard let eq = line.firstIndex(of: "=") else {
                warnings.append("line \(lineNo): expected `key = value`")
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            func int(_ range: ClosedRange<Int>) -> Int? {
                guard let n = Int(value), range.contains(n) else {
                    warnings.append("line \(lineNo): \(key) must be a whole number in \(range.lowerBound)...\(range.upperBound)")
                    return nil
                }
                return n
            }

            func bool() -> Bool? {
                switch value.lowercased() {
                case "true", "yes", "on", "1": return true
                case "false", "no", "off", "0": return false
                default:
                    warnings.append("line \(lineNo): \(key) must be true or false")
                    return nil
                }
            }

            switch key {
            case "max_items":
                if let n = int(1...1000) { settings.maxItems = n }
            case "text_length":
                if let n = int(5...500) { settings.textLength = n }
            case "image_size":
                if let n = int(16...512) { settings.imageSize = n }
            case "poll_interval":
                if let d = Double(value), (0.1...10).contains(d) {
                    settings.pollInterval = d
                } else {
                    warnings.append("line \(lineNo): poll_interval must be a number of seconds in 0.1...10")
                }
            case "hotkey":
                let lowered = value.lowercased()
                if lowered.isEmpty || lowered == "none" || lowered == "off" {
                    settings.hotkey = nil
                } else if HotKeySpec.parse(value) != nil {
                    settings.hotkey = value
                } else {
                    warnings.append("line \(lineNo): hotkey `\(value)` is not valid, e.g. cmd+alt+v")
                }
            case "launch_at_login":
                if let b = bool() { settings.launchAtLogin = b }
            case "ignore_concealed":
                if let b = bool() { settings.ignoreConcealed = b }
            case "ignored_apps":
                settings.ignoredApps = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            default:
                warnings.append("line \(lineNo): unknown key `\(key)`")
            }
        }
        return (settings, warnings)
    }

    /// Written to disk the first time CopyBar runs.
    public static let defaultFileContents = """
    # CopyBar settings. Changes are picked up automatically.
    # Lines starting with # are comments.

    # How many clipboard entries to keep (1-1000).
    max_items = 50

    # How many characters of copied text to show in the menu (5-500).
    text_length = 30

    # Size of image thumbnails in the menu, in points (16-512).
    image_size = 50

    # Global shortcut that opens the menu at the mouse pointer.
    # Modifiers: cmd, alt, ctrl, shift. Use `none` to turn it off.
    hotkey = cmd+alt+v

    # Start CopyBar when you log in.
    launch_at_login = true

    # Skip entries that apps mark as secret (password managers do this).
    ignore_concealed = true

    # Comma-separated bundle IDs of apps whose copies are never saved,
    # e.g. com.apple.keychainaccess, com.bitwarden.desktop
    ignored_apps =

    # How often to check the clipboard, in seconds (0.1-10).
    poll_interval = 0.5

    """
}
