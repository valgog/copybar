import Foundation

/// A parsed shortcut such as `cmd+alt+v`. Key codes are macOS virtual key
/// codes for the ANSI layout, as used by `RegisterEventHotKey`.
public struct HotKeySpec: Equatable {
    public struct Modifiers: OptionSet, Equatable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parses `mod+mod+key`. At least one modifier and exactly one key are required.
    public static func parse(_ string: String) -> HotKeySpec? {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: Modifiers = []
        var keyCode: UInt32?

        for part in parts {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "alt", "opt", "option", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            default:
                guard keyCode == nil, let code = keyCodes[part] else { return nil }
                keyCode = code
            }
        }
        guard let keyCode, !modifiers.isEmpty else { return nil }
        return HotKeySpec(keyCode: keyCode, modifiers: modifiers)
    }

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "space": 49, "`": 50,
    ]
}
