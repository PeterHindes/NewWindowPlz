import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onWindowClosed: () -> Void

    init(model: AppModel,
         onRequestAccess: @escaping () -> Void,
         onOpenSystemSettings: @escaping () -> Void,
         onRevealApp: @escaping () -> Void,
         onDismiss: @escaping () -> Void,
         onWindowClosed: @escaping () -> Void) {
        self.onWindowClosed = onWindowClosed

        let rootView = OnboardingView(
            model: model,
            onRequestAccess: onRequestAccess,
            onOpenSystemSettings: onOpenSystemSettings,
            onRevealApp: onRevealApp,
            onClose: onDismiss
        )
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to New Window Plz"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 600, height: 590))
        window.center()
        window.level = .normal

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(model: AppModel,
         settings: AppSettings,
         onRequestAccess: @escaping () -> Void,
         onOpenSystemSettings: @escaping () -> Void,
         onTestOverlay: @escaping () -> Void,
         onTestSwitcher: @escaping () -> Void,
         onRequestScreenCapture: @escaping () -> Void,
         onOpenScreenRecordingSettings: @escaping () -> Void,
         onCopyDiagnostics: @escaping () -> Void) {
        let rootView = SettingsView(
            model: model,
            settings: settings,
            onRequestAccess: onRequestAccess,
            onOpenSystemSettings: onOpenSystemSettings,
            onTestOverlay: onTestOverlay,
            onTestSwitcher: onTestSwitcher,
            onRequestScreenCapture: onRequestScreenCapture,
            onOpenScreenRecordingSettings: onOpenScreenRecordingSettings,
            onCopyDiagnostics: onCopyDiagnostics
        )
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "New Window Plz Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 580, height: 670))
        window.center()
        window.setFrameAutosaveName("NewWindowPlz.Settings")

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
