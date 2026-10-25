import AppKit

// `make install` and `make uninstall` run the old copy with this flag so it
// removes its own login item before it is replaced. macOS keys login items
// to the app's signature, so a new build can't remove the old entry.
if CommandLine.arguments.contains("--unregister-login-item") {
    LoginItem.unregister()
    exit(0)
}

// Only one CopyBar at a time, e.g. when a stale login item starts a second one.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .contains(where: { $0 != NSRunningApplication.current }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
