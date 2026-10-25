import AppKit

// `make install` and `make uninstall` run the old copy with this flag so it
// removes its own login item before it is replaced. macOS keys login items
// to the app's signature, so a new build can't remove the old entry.
// Exits with 1 if the login item is still there.
if CommandLine.arguments.contains("--unregister-login-item") {
    exit(LoginItem.unregister() ? 0 : 1)
}

/// Takes the single-instance lock and returns its file descriptor, which must
/// stay open for the life of the process. Exits if another CopyBar holds the
/// lock. If the lock file can't be used, logs it and runs anyway.
func acquireInstanceLock() -> Int32? {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = support.appendingPathComponent("CopyBar", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    } catch {
        log.error("Can't create \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
    }
    let path = dir.appendingPathComponent("CopyBar.lock").path
    let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, mode_t(0o600))
    guard fd >= 0 else {
        log.error("Can't open \(path, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
        return nil
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        let error = errno
        if error == EWOULDBLOCK { exit(0) }
        log.error("Can't lock \(path, privacy: .public): \(String(cString: strerror(error)), privacy: .public)")
        close(fd)
        return nil
    }
    return fd
}

// Only one CopyBar at a time, e.g. when a stale login item starts a second
// one. The first process holds an exclusive lock on a file; the kernel drops
// it when that process exits, so a crash can't leave a stale lock behind.
// Skipped without a bundle id (`swift run`).
let instanceLock: Int32? = Bundle.main.bundleIdentifier == nil ? nil : acquireInstanceLock()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
