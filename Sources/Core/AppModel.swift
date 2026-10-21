import AppKit
import Combine
import Foundation

enum OverlayReadiness: Equatable {
    case preparing
    case ready(refreshRate: Double)
    case unavailable(String)

    var label: String {
        switch self {
        case .preparing:
            return "Preparing Metal pipeline…"
        case .ready(let refreshRate):
            if refreshRate > 0 {
                return "Prewarmed · \(Int(refreshRate.rounded())) Hz display"
            }
            return "Prewarmed Metal overlay"
        case .unavailable(let message):
            return "Unavailable — \(message)"
        }
    }
}

final class AppModel: ObservableObject {
    @Published var permissionGranted = false
    @Published var monitoringActive = false
    @Published var altTabActive = false
    @Published var altTabWindowCount = 0
    @Published var switcherOpenMicroseconds: Double?
    @Published var screenCaptureGranted = false
    @Published var eventTapDescription = "Stopped"
    @Published var cachedDockTileCount = 0
    @Published var overlayReadiness: OverlayReadiness = .preparing
    @Published var overlayOpenMicroseconds: Double?
    @Published var overlayFirstFrameMicroseconds: Double?
    @Published var overlayRendererDescription = "Starting…"
    @Published var lastAction = "No actions yet"
    @Published var lastFailure: String?
    @Published var launchAtLogin = LoginItemManager.isEnabled
    @Published var loginItemError: String?

    func refreshPermission() {
        permissionGranted = AccessibilityPermission.isGranted
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = LoginItemManager.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginItemError = nil
            lastFailure = nil
        } catch {
            loginItemError = error.localizedDescription
            lastFailure = "Launch at login: \(error.localizedDescription)"
            Log.app.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
        refreshLaunchAtLogin()
    }
}
