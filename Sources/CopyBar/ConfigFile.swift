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

    /// Writes the default config. Only what CopyBar creates itself is made
    /// private (folder 0700, file 0600); an existing `~/.config` or config
    /// file keeps its permissions.
    func createIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        let folder = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: false,
                                       attributes: [.posixPermissions: 0o700])
            }
            try Settings.defaultFileContents.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
