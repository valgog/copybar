import AppKit
import ImageIO

struct ClipItem: Codable {
    enum Kind: String, Codable {
        case text, image
    }

    let id: UUID
    var date: Date
    let kind: Kind
    /// Plain text of a text item.
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
/// only read when an item is picked, so large images don't stay in memory.
final class HistoryStore {
    private(set) var items: [ClipItem] = []
    var maxItems: Int {
        didSet { if maxItems != oldValue { trim(); save() } }
    }

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var thumbnails: [UUID: NSImage] = [:]
    private var thumbnailSize = 0

    init(maxItems: Int) {
        self.maxItems = maxItems
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("CopyBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// Adds a new entry at the top. A repeated copy replaces the older entry.
    func add(kind: ClipItem.Kind, text: String?, digest: String, representations: [(String, Data)],
             pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        if let existing = items.first(where: { $0.digest == digest }) {
            remove(existing.id)
        }
        let item = ClipItem(id: UUID(), date: Date(), kind: kind, text: text, digest: digest,
                            types: representations.map { $0.0 }, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let itemDir = folder(for: item.id)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            for (index, (_, data)) in representations.enumerated() {
                try data.write(to: itemDir.appendingPathComponent("\(index).bin"))
            }
        } catch {
            log.error("Could not save clipboard item: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: itemDir)
            return
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

    private func trim() {
        while items.count > maxItems, let last = items.last {
            remove(last.id)
        }
    }

    private func folder(for id: UUID) -> URL {
        directory.appendingPathComponent("items", isDirectory: true).appendingPathComponent(id.uuidString)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        let fm = FileManager.default
        items = saved.filter { fm.fileExists(atPath: folder(for: $0.id).path) }
        trim()
        removeOrphans()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
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
