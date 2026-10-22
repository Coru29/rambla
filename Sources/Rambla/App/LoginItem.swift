import ServiceManagement

/// "Arrancar con la Mac" through SMAppService (macOS 13+): no helper app, no launch agent file.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    /// Registered, but macOS waits for the user to allow it in System Settings → General → Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
