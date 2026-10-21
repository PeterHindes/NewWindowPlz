import AppKit
import Combine

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let model: AppModel
    private let settings: AppSettings

    private let onOpenSettings: () -> Void
    private let onOpenOnboarding: () -> Void
    private let onTestOverlay: () -> Void
    private let onTestSwitcher: () -> Void
    private let onCopyDiagnostics: () -> Void

    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel,
         settings: AppSettings,
         onOpenSettings: @escaping () -> Void,
         onOpenOnboarding: @escaping () -> Void,
         onTestOverlay: @escaping () -> Void,
         onTestSwitcher: @escaping () -> Void,
         onCopyDiagnostics: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.onTestOverlay = onTestOverlay
        self.onTestSwitcher = onTestSwitcher
        self.onCopyDiagnostics = onCopyDiagnostics
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "New Window Plz"
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        refreshIcon()

        model.$monitoringActive
            .combineLatest(settings.$monitoringEnabled, model.$permissionGranted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        model.$overlayReadiness
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        model.$altTabActive
            .combineLatest(settings.$altTabEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func refreshMenu() {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let dockActive = settings.monitoringEnabled && model.monitoringActive
        let switcherActive = settings.altTabEnabled && model.altTabActive
        let status = model.permissionGranted
            ? (dockActive || switcherActive ? "Monitoring" : "Paused")
            : "Permission needed"
        let header = NSMenuItem(title: "New Window Plz — \(status)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !model.permissionGranted {
            let grant = NSMenuItem(
                title: "Grant Accessibility Access…",
                action: #selector(grantAccess),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
        }

        let toggle = NSMenuItem(
            title: "Open New Window on Dock Click",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = settings.monitoringEnabled ? .on : .off
        menu.addItem(toggle)

        let switcherToggle = NSMenuItem(
            title: "⌥Tab Window Switcher",
            action: #selector(toggleAltTab),
            keyEquivalent: ""
        )
        switcherToggle.target = self
        switcherToggle.state = settings.altTabEnabled ? .on : .off
        menu.addItem(switcherToggle)

        let snapshots = NSMenuItem(
            title: "Show Window Snapshots",
            action: #selector(toggleSnapshots),
            keyEquivalent: ""
        )
        snapshots.target = self
        snapshots.state = settings.showWindowSnapshots ? .on : .off
        snapshots.isEnabled = settings.altTabEnabled
        menu.addItem(snapshots)

        menu.addItem(.separator())

        let overlayReady: Bool
        if case .ready = model.overlayReadiness {
            overlayReady = true
        } else {
            overlayReady = false
        }

        let switcher = NSMenuItem(
            title: "Preview App Switcher",
            action: #selector(testSwitcher),
            keyEquivalent: ""
        )
        switcher.target = self
        switcher.isEnabled = overlayReady
        menu.addItem(switcher)

        let overlay = NSMenuItem(title: "Test Metal Overlay", action: #selector(testOverlay), keyEquivalent: "t")
        overlay.keyEquivalentModifierMask = [.command]
        overlay.target = self
        overlay.isEnabled = overlayReady
        menu.addItem(overlay)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboarding = NSMenuItem(title: "Welcome & Setup…", action: #selector(openOnboarding), keyEquivalent: "")
        onboarding.target = self
        menu.addItem(onboarding)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)

        let diagnostics = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit New Window Plz", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func refreshIcon() {
        let dockActive = settings.monitoringEnabled && model.monitoringActive
        let switcherActive = settings.altTabEnabled && model.altTabActive
        let isActive = model.permissionGranted && (dockActive || switcherActive)
        let symbol = isActive ? "plus.rectangle.on.rectangle" : "rectangle.on.rectangle.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "New Window Plz")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.alphaValue = isActive ? 1.0 : 0.55
        if !model.permissionGranted {
            statusItem.button?.toolTip = "New Window Plz — Accessibility permission needed"
        } else if dockActive && switcherActive {
            statusItem.button?.toolTip = "New Window Plz — Dock new windows + ⌥Tab window switcher"
        } else if dockActive {
            statusItem.button?.toolTip = "New Window Plz — monitoring Dock clicks"
        } else if switcherActive {
            statusItem.button?.toolTip = "New Window Plz — ⌥Tab window switcher ready"
        } else {
            statusItem.button?.toolTip = "New Window Plz — paused"
        }
    }

    @objc private func grantAccess() {
        AccessibilityPermission.requestPrompt()
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func toggleMonitoring() {
        settings.monitoringEnabled.toggle()
    }

    @objc private func toggleAltTab() {
        settings.altTabEnabled.toggle()
    }

    @objc private func toggleSnapshots() {
        settings.showWindowSnapshots.toggle()
        if settings.showWindowSnapshots && !model.screenCaptureGranted {
            _ = ScreenCapturePermission.request()
        }
    }

    @objc private func testOverlay() {
        onTestOverlay()
    }

    @objc private func testSwitcher() {
        onTestSwitcher()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openOnboarding() {
        onOpenOnboarding()
    }

    @objc private func toggleLoginItem() {
        model.setLaunchAtLogin(!model.launchAtLogin)
    }

    @objc private func copyDiagnostics() {
        onCopyDiagnostics()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
