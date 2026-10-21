import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.permissions.info("Accessibility prompt requested. trusted=\(trusted, privacy: .public)")
        return trusted
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
