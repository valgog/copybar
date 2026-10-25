import CopyBarCore
import Foundation

/// Loads `~/.config/copybar/config` and reloads it when it changes on disk.
final class ConfigFile {
    let url: URL
    private(set) var settings = Settings()
    private var lastModified: Date?
    private var timer: Timer?
    var onChange: ((Settings) -> Void)?

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/copybar/config")
        createIfMissing()
        reload()
    }

    func startWatching() {
        // Editors often replace the file instead of writing in place, so a
        // cheap modification-date check is more reliable than a file watcher.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.modificationDate() != self.lastModified {
                self.reload()
                self.onChange?(self.settings)
            }
        }
    }

    func createIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Settings.defaultFileContents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("Could not create config file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reload() {
        lastModified = modificationDate()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            settings = Settings()
            return
        }
        let (parsed, warnings) = Settings.parse(text)
        for warning in warnings {
            log.warning("config: \(warning, privacy: .public)")
        }
        settings = parsed
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
