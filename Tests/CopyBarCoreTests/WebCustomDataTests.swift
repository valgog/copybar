@testable import CopyBarCore
import XCTest

final class WebCustomDataTests: XCTestCase {
    /// Builds the pickle Chrome writes for `entries`.
    private func pickle(_ entries: [(String, String)], count: Int? = nil) -> Data {
        var payload = Data()
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
        }
        func append(_ string: String) {
            let units = Array(string.utf16)
            append(UInt32(units.count))
            for unit in units {
                withUnsafeBytes(of: unit.littleEndian) { payload.append(contentsOf: $0) }
            }
            while payload.count % 4 != 0 { payload.append(0) }
        }
        append(UInt32(count ?? entries.count))
        for (type, value) in entries {
            append(type)
            append(value)
        }
        var data = Data()
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        return data + payload
    }

    func testReadsEntries() throws {
        let data = pickle([("application/x-vnd.google-docs-x", "{\"a\":1}"), ("text/x-é", "ünï 😀")])
        let entries = try XCTUnwrap(WebCustomData.entries(data))
        XCTAssertEqual(entries.map(\.type), ["application/x-vnd.google-docs-x", "text/x-é"])
        XCTAssertEqual(entries.map(\.value), ["{\"a\":1}", "ünï 😀"])
    }

    func testEmpty() throws {
        XCTAssertEqual(try XCTUnwrap(WebCustomData.entries(pickle([]))).count, 0)
    }

    func testRejectsMalformedData() {
        XCTAssertNil(WebCustomData.entries(Data()))
        XCTAssertNil(WebCustomData.entries(Data([1, 2, 3])))
        // Claims more entries than it holds.
        XCTAssertNil(WebCustomData.entries(pickle([("a", "b")], count: 2)))
        // Truncated in the middle of a string.
        let data = pickle([("type", "a longer value")])
        XCTAssertNil(WebCustomData.entries(data.prefix(data.count - 8)))
    }

    func testStopsAtMaxEntries() throws {
        let data = pickle([("a", "1"), ("b", "2"), ("c", "3")])
        XCTAssertEqual(try XCTUnwrap(WebCustomData.entries(data, maxEntries: 2)).map(\.type), ["a", "b"])
    }
}
