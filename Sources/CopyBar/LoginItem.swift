import Foundation
import ServiceManagement

enum LoginItem {
    static func set(_ enabled: Bool) {
        // Only an installed .app can be a login item, not a bare `swift run` binary.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, isListed(service.status) {
                try service.unregister()
            }
        } catch {
            log.error("Could not update login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the login item and returns whether it is gone. Errors also go
    /// to stderr, because `make uninstall` runs this from a terminal.
    @discardableResult
    static func unregister() -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return true }
        let service = SMAppService.mainApp
        guard isListed(service.status) else { return true }
        do {
            try service.unregister()
        } catch {
            log.error("Could not remove login item: \(error.localizedDescription, privacy: .public)")
            FileHandle.standardError.write(Data("Could not remove login item: \(error.localizedDescription)\n".utf8))
        }
        return !isListed(service.status)
    }

    /// `.requiresApproval` is an item the user switched off in System
    /// Settings. It is still listed there, so it has to be unregistered too.
    private static func isListed(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
