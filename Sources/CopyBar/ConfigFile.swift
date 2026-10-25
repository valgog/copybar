import CopyBarCore
import Foundation

/// Loads `~/.config/copybar/config` and reloads it when it changes on disk.
final class ConfigFile {
    let url: URL
    private(set) var settings = Settings()
    private var lastModified: Date?
    private var timer: Timer?
    var onChange: ((Settings) -> Void)?

    /// A config file is a few hundred bytes; anything bigger is a mistake.
    private static let maxFileSize = 64 * 1024

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/copybar/config")
        createIfMissing()
        reload()
    }

    func startWatching() {
        timer?.invalidate()
        // Editors often replace the file instead of writing in place, so a
        // cheap modification-date check is more reliable than a file watcher.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.modificationDate() != self.lastModified {
                self.reload()
                self.onChange?(self.settings)
            }
        }
        // .common keeps it firing while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Writes the default config. Only what CopyBar creates itself is made
    /// private (folder 0700, file 0600); an existing `~/.config` or config
    /// file keeps its permissions.
    func createIfMissing() {
        let fm = FileManager.default
        // `attributesOfItem` doesn't follow symlinks, so a symlink counts as
        // existing even when its target is missing: a dotfiles link is never
        // replaced or written through.
        guard (try? fm.attributesOfItem(atPath: url.path)) == nil else { return }
        let folder = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: false,
                                       attributes: [.posixPermissions: 0o700])
            }
        } catch {
            log.error("Could not create config folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        // O_EXCL fails if anything, even a dangling symlink, appeared at the
        // path in the meantime.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            let code = errno
            if code != EEXIST {
                log.error("Could not create config file: \(String(cString: strerror(code)), privacy: .public)")
            }
            return
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(Settings.defaultFileContents.utf8))
        } catch {
            log.error("Could not write config file: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: url)
        }
    }

    private func reload() {
        lastModified = modificationDate()
        guard let text = readText() else {
            settings = Settings()
            return
        }
        let (parsed, warnings) = Settings.parse(text)
        for warning in warnings {
            log.warning("config: \(warning, privacy: .public)")
        }
        settings = parsed
    }

    /// The config text, read through symlinks (dotfiles setups link it), but
    /// only from a regular file of at most `maxFileSize` bytes. O_NONBLOCK
    /// keeps the open from hanging on a FIFO, and the type is checked on the
    /// opened file, so it can't be swapped after the check.
    private func readText() -> String? {
        let path = url.path
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            let code = errno
            if code != ENOENT {
                log.warning("config: could not open \(path, privacy: .public): \(String(cString: strerror(code)), privacy: .public); using defaults")
            }
            return nil
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            log.warning("config: \(path, privacy: .public) is not a regular file; using defaults")
            return nil
        }
        guard info.st_size <= off_t(Self.maxFileSize) else {
            log.warning("config: \(path, privacy: .public) is larger than 64 KB; using defaults")
            return nil
        }
        let data: Data
        do {
            data = try handle.read(upToCount: Self.maxFileSize) ?? Data()
        } catch {
            log.warning("config: could not read \(path, privacy: .public): \(error.localizedDescription, privacy: .public); using defaults")
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            log.warning("config: \(path, privacy: .public) is not valid UTF-8; using defaults")
            return nil
        }
        return text
    }

    private func modificationDate() -> Date? {
        // Follow symlinks so edits to a linked file are noticed.
        let path = url.resolvingSymlinksInPath().path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
