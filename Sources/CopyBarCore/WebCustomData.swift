import Foundation

/// Reads Chrome's `org.chromium.web-custom-data` pasteboard data: the
/// formats a web page put on the clipboard itself (`DataTransfer.setData`
/// with its own MIME types), such as Google Docs and Slides content.
///
/// The data is a Chromium `base::Pickle`: a 32-bit payload size, a 32-bit
/// entry count, then for each entry the type and the value as strings. A
/// string is a 32-bit length in UTF-16 code units followed by the UTF-16
/// data, padded to 4 bytes. Integers are little-endian.
public enum WebCustomData {
    /// The (type, value) entries, or nil if `data` isn't in this format.
    /// Stops at `maxEntries` so malformed data can't claim millions.
    public static func entries(_ data: Data, maxEntries: Int = 100) -> [(type: String, value: String)]? {
        var reader = Reader(bytes: [UInt8](data))
        guard let payloadSize = reader.uint32(), Int(payloadSize) <= data.count - 4,
              let count = reader.uint32() else { return nil }
        var result: [(type: String, value: String)] = []
        for _ in 0..<min(Int(count), maxEntries) {
            guard let type = reader.string(), let value = reader.string() else { return nil }
            result.append((type: type, value: value))
        }
        return result
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func uint32() -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            let value = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            offset += 4
            return value
        }

        mutating func string() -> String? {
            guard let length = uint32().map(Int.init) else { return nil }
            let byteCount = length * 2
            guard byteCount <= bytes.count - offset else { return nil }
            var units: [UInt16] = []
            units.reserveCapacity(length)
            for index in stride(from: offset, to: offset + byteCount, by: 2) {
                units.append(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            }
            offset += (byteCount + 3) & ~3
            return String(decoding: units, as: UTF16.self)
        }
    }
}
