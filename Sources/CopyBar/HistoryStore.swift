import AppKit
import CopyBarCore
import ImageIO

/// The contents of `index.json`.
private struct SavedIndex: Codable {
    let version: Int
    let items: [ClipItem]
}

struct ClipItem: Codable {
    enum Kind: String, Codable {
        /// Plain text, with its formatted versions if any.
        case text
        /// An image, saved as PNG.
        case image
        /// Anything else apps put on the pasteboard, such as a slide copied
        /// in Google Slides: every format, saved as is.
        case rich
    }

    let id: UUID
    var date: Date
    let kind: Kind
    /// The start of a text item's plain text, at most
    /// `HistoryStore.storedTextLength` characters: enough for the menu title
    /// and tooltip. The full text is in the item's saved
    /// `public.utf8-plain-text` data (see `HistoryStore.fullText(of:)`).
    /// For a rich item, the visible text of its HTML, or the name of the
    /// app it was copied in.
    let text: String?
    /// Used to spot repeated copies.
    let digest: String
    /// Pasteboard types saved for this item, in the order they were copied.
    let types: [String]
    let pixelWidth: Int?
    let pixelHeight: Int?
}

/// Keeps the clipboard history in memory and mirrors it to
/// `~/Library/Application Support/CopyBar`. Item data lives on disk and is
/// only read when an item is picked, so large images and long texts don't
/// stay in memory or in `index.json`. The history can hold passwords and
/// other secrets, so the folders are created 0700 and the files 0600.
final class HistoryStore {
    /// Characters of plain text kept in the index: covers the longest menu
    /// title (500) and the tooltip (1000).
    static let storedTextLength = 1000

    private(set) var items: [ClipItem] = []
    var maxItems: Int {
        didSet { if maxItems != oldValue { trim(); save() } }
    }

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    /// Bump when `ClipItem` or the item files change in a way older history
    /// can't be read with. History in any other format is deleted on start.
    private static let formatVersion = 1
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600
    private var thumbnails: [UUID: NSImage] = [:]
    private var thumbnailSize = 0

    init(maxItems: Int) {
        self.maxItems = maxItems
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("CopyBar", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: Self.directoryPermissions])
        // The folder may already exist with looser permissions. Locking it
        // down is enough: what's inside is then out of reach for others.
        do {
            try fm.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
        } catch {
            log.warning("Could not restrict permissions of \(self.directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        load()
    }

    /// Adds a new entry at the top. A repeated copy replaces the older entry,
    /// but only once the new one is saved, so a failed write loses nothing.
    func add(kind: ClipItem.Kind, text: String?, digest: String, representations: [(String, Data)],
             pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        let item = ClipItem(id: UUID(), date: Date(), kind: kind, text: text.map(Self.shortened),
                            digest: digest,
                            types: representations.map { $0.0 }, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let itemDir = folder(for: item.id)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: Self.directoryPermissions])
            for (index, (_, data)) in representations.enumerated() {
                try write(data, to: itemDir.appendingPathComponent("\(index).bin"))
            }
        } catch {
            log.error("Could not save clipboard item: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: itemDir)
            return
        }
        if let existing = items.first(where: { $0.digest == digest }) {
            remove(existing.id)
        }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func moveToTop(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.date = Date()
        items.insert(item, at: 0)
        save()
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: folder(for: item.id))
        }
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    func item(_ id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    /// The saved pasteboard data of an item, as (type, data) pairs.
    func representations(of item: ClipItem) -> [(String, Data)] {
        let itemDir = folder(for: item.id)
        return item.types.enumerated().compactMap { index, type in
            guard let data = try? Data(contentsOf: itemDir.appendingPathComponent("\(index).bin")) else { return nil }
            return (type, data)
        }
    }

    /// The full plain text of a text item, read from its saved
    /// `public.utf8-plain-text` data. Falls back to the stored start.
    func fullText(of item: ClipItem) -> String? {
        guard let index = item.types.firstIndex(of: NSPasteboard.PasteboardType.string.rawValue),
              let data = try? Data(contentsOf: folder(for: item.id).appendingPathComponent("\(index).bin")),
              let text = String(data: data, encoding: .utf8) else { return item.text }
        return text
    }

    /// A thumbnail that fits in a `size`×`size` point box, cached per item.
    func thumbnail(of item: ClipItem, size: Int) -> NSImage? {
        if size != thumbnailSize {
            thumbnails.removeAll()
            thumbnailSize = size
        }
        if let cached = thumbnails[item.id] { return cached }
        guard item.kind == .image else { return nil }

        let url = folder(for: item.id).appendingPathComponent("0.bin")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size * 2, // sharp on Retina screens
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        // Fit the box, but never blow up a tiny image past one point per pixel.
        let scale = min(CGFloat(size) / max(width, height), 1)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width * scale, height: height * scale))
        thumbnails[item.id] = image
        return image
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    /// Leading whitespace and invisible characters are dropped first, so
    /// they can't push the visible text out of the stored start.
    private static func shortened(_ text: String) -> String {
        Preview.visiblePrefix(text, maxLength: storedTextLength)
    }

    private func trim() {
        while items.count > maxItems, let last = items.last {
            remove(last.id)
        }
    }

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent("items", isDirectory: true).appendingPathComponent(id.uuidString)
    }

    /// Loads the index, or deletes the whole history when the index is
    /// missing, unreadable or from another format version.
    private func load() {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode(SavedIndex.self, from: data),
           index.version == Self.formatVersion {
            items = index.items.filter { fm.fileExists(atPath: folder(for: $0.id).path) }
            trim()
        } else if fm.fileExists(atPath: indexURL.path) {
            log.warning("Deleting clipboard history saved in an incompatible format")
            try? fm.removeItem(at: indexURL)
        }
        // With no index loaded this deletes every item folder.
        removeOrphans()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(SavedIndex(version: Self.formatVersion, items: items))
            try write(data, to: indexURL, options: .atomic)
        } catch {
            log.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes a file readable only by the user. An atomic write replaces the
    /// file, so the permissions are set afterwards; the folder is already
    /// private, so nobody else can open the file in between.
    private func write(_ data: Data, to url: URL, options: Data.WritingOptions = []) throws {
        try data.write(to: url, options: options)
        try FileManager.default.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: url.path)
    }

    /// Deletes item folders that are no longer in the index.
    private func removeOrphans() {
        let itemsDir = directory.appendingPathComponent("items", isDirectory: true)
        let known = Set(items.map(\.id.uuidString))
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: itemsDir.path)) ?? []
        for name in folders where !known.contains(name) {
            try? FileManager.default.removeItem(at: itemsDir.appendingPathComponent(name))
        }
    }
}
