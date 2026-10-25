import ServiceManagement

enum LoginItem {
    static func set(_ enabled: Bool) {
        // Only an installed .app can be a login item, not a bare `swift run` binary.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            log.error("Could not update login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func unregister() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            log.error("Could not remove login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
