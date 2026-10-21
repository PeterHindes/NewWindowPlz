import AppKit
import Combine
import Metal
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let settings = AppSettings.shared

    private var statusBarController: StatusBarController!
    private var overlayHost: OverlayHost!
    private var dockClickController: DockClickController!
    private var newWindowController: NewWindowController!
    private var altTabController: AltTabController!

    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var permissionTimer: Timer?
    private var healthTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastPermissionState = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if handleOverlayPreviewIfRequested() {
            return
        }

        if handleAltTabPreviewIfRequested() {
            return
        }

        if CommandLine.arguments.contains("--overlay-benchmark") {
            runOverlayBenchmark()
            return
        }

        if CommandLine.arguments.contains("--switcher-benchmark") {
            runSwitcherBenchmark()
            return
        }

        if CommandLine.arguments.contains("--self-test") {
            runSelfTest()
            return
        }

        if CommandLine.arguments.contains("--dock-diagnostics") {
            runDockDiagnostics()
            return
        }

        if let index = CommandLine.arguments.firstIndex(of: "--open-new-window"),
           CommandLine.arguments.indices.contains(index + 1) {
            runOpenNewWindowDiagnostic(bundleIdentifier: CommandLine.arguments[index + 1])
            return
        }

        setupMainMenu()
        model.refreshPermission()
        model.refreshLaunchAtLogin()
        model.screenCaptureGranted = ScreenCapturePermission.isGranted
        lastPermissionState = model.permissionGranted

        let inspector = DockInspector()
        let geometryCache = DockGeometryCache()
        newWindowController = NewWindowController(model: model)
        let eventTap = DockEventTap(inspector: inspector, geometryCache: geometryCache)
        dockClickController = DockClickController(
            inspector: inspector,
            geometryCache: geometryCache,
            eventTap: eventTap,
            newWindowController: newWindowController,
            model: model,
            settings: settings
        )

        overlayHost = OverlayHost(model: model)
        altTabController = AltTabController(overlayHost: overlayHost, model: model, settings: settings)
        statusBarController = StatusBarController(
            model: model,
            settings: settings,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenOnboarding: { [weak self] in self?.showOnboarding() },
            onTestOverlay: { [weak self] in self?.overlayHost.showDemo() },
            onTestSwitcher: { [weak self] in self?.altTabController.preview() },
            onCopyDiagnostics: { [weak self] in self?.copyDiagnostics() }
        )

        observeSettings()
        startTimers()
        applyRuntimeState()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.overlayHost.prepare()
        }

        if CommandLine.arguments.contains("--demo-overlay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.overlayHost.showDemo()
            }
        }

        let skipOnboarding = CommandLine.arguments.contains("--no-onboarding")
        if !skipOnboarding && !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        healthTimer?.invalidate()
        dockClickController?.stop()
        altTabController?.stop()
        overlayHost?.hide()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func observeSettings() {
        settings.$monitoringEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyRuntimeState()
                self?.statusBarController.refreshMenu()
            }
            .store(in: &cancellables)

        settings.$altTabEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAltTabState()
                self?.statusBarController.refreshMenu()
            }
            .store(in: &cancellables)

        model.$permissionGranted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusBarController.refreshMenu()
            }
            .store(in: &cancellables)
    }

    private func startTimers() {
        let permission = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.pollPermission()
        }
        RunLoop.main.add(permission, forMode: .common)
        permissionTimer = permission

        let health = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
        RunLoop.main.add(health, forMode: .common)
        healthTimer = health
    }

    private func pollPermission() {
        let screenCaptureGranted = ScreenCapturePermission.isGranted
        if screenCaptureGranted != model.screenCaptureGranted {
            model.screenCaptureGranted = screenCaptureGranted
            Log.permissions.info("Screen Recording status changed to \(screenCaptureGranted, privacy: .public)")
        }

        let granted = AccessibilityPermission.isGranted
        guard granted != model.permissionGranted || granted != lastPermissionState else {
            return
        }
        lastPermissionState = granted
        model.permissionGranted = granted
        Log.permissions.info("Accessibility status changed to \(granted, privacy: .public)")

        if granted {
            applyRuntimeState()
        } else {
            dockClickController.stop()
            altTabController.stop()
            model.lastFailure = "Accessibility access was revoked. Grant it again to resume monitoring."
        }
    }

    private func applyRuntimeState() {
        applyMonitoringState()
        applyAltTabState()
    }

    private func applyMonitoringState() {
        model.refreshPermission()
        guard model.permissionGranted, settings.monitoringEnabled else {
            dockClickController?.stop()
            return
        }
        _ = dockClickController?.start()
    }

    private func applyAltTabState() {
        model.refreshPermission()
        guard model.permissionGranted, settings.altTabEnabled else {
            altTabController?.stop()
            return
        }
        altTabController?.start()
    }

    private func performHealthCheck() {
        if !model.permissionGranted || !settings.monitoringEnabled {
            if dockClickController?.isMonitoring == true {
                dockClickController.stop()
            }
        } else if dockClickController?.isMonitoring == false {
            _ = dockClickController.start()
        }

        if !model.permissionGranted || !settings.altTabEnabled {
            if altTabController?.isRunning == true {
                altTabController.stop()
            }
        } else if altTabController?.isRunning == false {
            altTabController.start()
        }
    }

    private func showOnboarding() {
        if let existing = onboardingWindowController {
            existing.present()
            return
        }

        let controller = OnboardingWindowController(
            model: model,
            onRequestAccess: { [weak self] in
                AccessibilityPermission.requestPrompt()
                self?.model.refreshPermission()
                self?.applyRuntimeState()
            },
            onOpenSystemSettings: {
                AccessibilityPermission.openSystemSettings()
            },
            onRevealApp: {
                AccessibilityPermission.revealAppInFinder()
            },
            onDismiss: { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
                self?.applyRuntimeState()
            },
            onWindowClosed: { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.onboardingWindowController = nil
                self?.applyRuntimeState()
            }
        )
        onboardingWindowController = controller
        controller.present()
    }

    private func showSettings() {
        if let existing = settingsWindowController {
            existing.present()
            return
        }

        let controller = SettingsWindowController(
            model: model,
            settings: settings,
            onRequestAccess: { [weak self] in
                AccessibilityPermission.requestPrompt()
                self?.model.refreshPermission()
                self?.applyRuntimeState()
            },
            onOpenSystemSettings: {
                AccessibilityPermission.openSystemSettings()
            },
            onTestOverlay: { [weak self] in
                self?.overlayHost.showDemo()
            },
            onTestSwitcher: { [weak self] in
                self?.altTabController.preview()
            },
            onRequestScreenCapture: { [weak self] in
                _ = ScreenCapturePermission.request()
                self?.model.screenCaptureGranted = ScreenCapturePermission.isGranted
            },
            onOpenScreenRecordingSettings: {
                ScreenCapturePermission.openSystemSettings()
            },
            onCopyDiagnostics: { [weak self] in
                self?.copyDiagnostics()
            }
        )
        settingsWindowController = controller
        controller.present()
    }

    private func copyDiagnostics() {
        let overlayState: String
        switch model.overlayReadiness {
        case .preparing:
            overlayState = "preparing"
        case .ready(let rate):
            overlayState = "ready at \(Int(rate.rounded())) Hz"
        case .unavailable(let message):
            overlayState = "unavailable: \(message)"
        }

        let text = """
        New Window Plz diagnostics
        --------------------------
        Bundle: \(Bundle.main.bundlePath)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility trusted: \(model.permissionGranted)
        Screen Recording trusted: \(model.screenCaptureGranted)
        Snapshot option: \(settings.showWindowSnapshots)
        Monitoring requested: \(settings.monitoringEnabled)
        Dock event tap active: \(model.monitoringActive)
        Dock event tap status: \(model.eventTapDescription)
        Alt-Tab event tap active: \(model.altTabActive)
        Alt-Tab current-Space windows cached: \(model.altTabWindowCount)
        Cached Dock app tiles: \(model.cachedDockTileCount)
        Overlay: \(overlayState)
        Overlay renderer: \(model.overlayRendererDescription)
        Overlay open: \(model.overlayOpenMicroseconds.map { String(format: "%.2f ms", $0 / 1_000) } ?? "not measured")
        Last action: \(model.lastAction)
        Last failure: \(model.lastFailure ?? "none")
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.app.info("Diagnostics copied to pasteboard.")
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: "New Window Plz")
        appMenu.addItem(withTitle: "About New Window Plz",
                        action: #selector(showAbout),
                        keyEquivalent: "")
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(showSettingsFromMenu),
                        keyEquivalent: ",")
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit New Window Plz",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenu.items.last?.target = NSApp
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "A prewarmed Metal window switcher and a Dock click interceptor in one tiny menu-bar app.\n\nOption-Tab switches current-Space windows. Plain Dock clicks open new windows.\n\nAccessibility only. Optional Screen Recording for window snapshots. No network.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "New Window Plz",
            .applicationVersion: "1.2"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    private func runOverlayBenchmark() {
        let benchmarkModel = AppModel()
        let host = OverlayHost(model: benchmarkModel)
        host.prepare()

        var samples: [Double] = []
        var endToEndSamples: [Double] = []
        var listSamples: [Double] = []
        var prepareSamples: [Double] = []
        let iterations = 16

        func runIteration(_ index: Int) {
            guard index < iterations else {
                let sorted = samples.sorted()
                let median = sorted[sorted.count / 2]
                let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                let minimum = sorted.first ?? 0
                let maximum = sorted.last ?? 0
                let refresh = CGDisplayCopyDisplayMode(CGMainDisplayID())?.refreshRate ?? 60
                print(String(
                    format: "OVERLAY_BENCHMARK iterations=%d median_us=%.1f p95_us=%.1f min_us=%.1f max_us=%.1f refresh=%.0f",
                    iterations, median, p95, minimum, maximum, refresh
                ))
                host.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    exit(0)
                }
                return
            }

            host.showDemo(autoHideAfter: nil)
            if let sample = benchmarkModel.overlayOpenMicroseconds {
                samples.append(sample)
            }
            host.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                runIteration(index + 1)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            runIteration(0)
        }
    }

    private func runSwitcherBenchmark() {
        let benchmarkModel = AppModel()
        let host = OverlayHost(model: benchmarkModel)
        host.prepare()

        var samples: [Double] = []
        var endToEndSamples: [Double] = []
        var windows: [AltTabWindow] = []
        var coldScanMicroseconds: Double = 0
        let iterations = 16

        func runIteration(_ index: Int) {
            guard index < iterations else {
                let sorted = samples.sorted()
                let median = sorted[sorted.count / 2]
                let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                let sortedEndToEnd = endToEndSamples.sorted()
                let endToEndMedian = sortedEndToEnd[sortedEndToEnd.count / 2]
                let endToEndP95 = sortedEndToEnd[min(sortedEndToEnd.count - 1, Int(Double(sortedEndToEnd.count) * 0.95))]
                print(String(
                    format: "SWITCHER_BENCHMARK windows=%d iterations=%d reveal_median_us=%.1f reveal_p95_us=%.1f warm_end_to_end_median_us=%.1f warm_end_to_end_p95_us=%.1f cold_scan_us=%.1f",
                    windows.count, iterations, median, p95, endToEndMedian, endToEndP95, coldScanMicroseconds
                ))
                host.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    exit(0)
                }
                return
            }

            let start = CACurrentMediaTime()
            host.prepareWindowSwitcherCache(windows: windows)
            host.showWindowSwitcher(
                windows: windows,
                selectedIndex: min(index % 2, windows.count - 1),
                showSnapshots: false
            )
            endToEndSamples.append((CACurrentMediaTime() - start) * 1_000_000)
            if let sample = benchmarkModel.overlayOpenMicroseconds {
                samples.append(sample)
            }
            host.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                runIteration(index + 1)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let scanStart = CACurrentMediaTime()
            windows = CurrentSpaceWindows.snapshot()
            coldScanMicroseconds = (CACurrentMediaTime() - scanStart) * 1_000_000
            guard !windows.isEmpty else {
                print("SWITCHER_BENCHMARK no current-Space windows")
                exit(1)
            }
            host.prepareWindowSwitcherCache(windows: windows)
            runIteration(0)
        }
    }

    private func runDockDiagnostics() {
        let trusted = AccessibilityPermission.isGranted
        print("Accessibility trusted: \(trusted)")
        guard trusted else {
            print("Grant Accessibility access to New Window Plz first.")
            exit(2)
        }

        let inspector = DockInspector()
        let snapshot = inspector.scan()
        print("Dock application tiles: \(snapshot.tiles.count)")
        for tile in snapshot.tiles {
            let app = RunningApplicationResolver.application(for: tile)
            print("TILE title=\(tile.title) bundle=\(tile.bundleIdentifier ?? "?") running=\(tile.isRunning) pid=\(app?.processIdentifier ?? 0) frame=\(tile.frame)")
        }

        if let location = CGEvent(source: nil)?.location {
            print("Pointer under mouse: \(location)")
            switch inspector.inspectApplicationTile(at: location) {
            case .application(let tile):
                print("POINTER TILE \(tile.title) bundle=\(tile.bundleIdentifier ?? "?") running=\(tile.isRunning)")
            case .notApplication:
                print("Pointer is not over an application Dock tile.")
            case .unavailable:
                print("Pointer inspection unavailable.")
            }
        }

        let resolver = NewWindowMenuResolver()
        for tile in snapshot.tiles where tile.isRunning {
            guard let app = RunningApplicationResolver.application(for: tile),
                  app.activationPolicy == .regular else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.45)
            if let match = resolver.match(for: element, pid: app.processIdentifier) {
                print("MENU \(tile.title) → \(match.title) score=\(match.score)")
            } else {
                print("MENU \(tile.title) → none")
            }
        }
        exit(0)
    }

    private func runOpenNewWindowDiagnostic(bundleIdentifier: String) {
        guard AccessibilityPermission.isGranted else {
            print("Accessibility is not trusted.")
            exit(2)
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            print("No running application with bundle identifier \(bundleIdentifier).")
            exit(3)
        }

        let diagnosticModel = AppModel()
        let controller = NewWindowController(model: diagnosticModel)
        let tile = DockTile(
            title: app.localizedName ?? bundleIdentifier,
            frame: .zero,
            isRunning: true,
            bundleIdentifier: bundleIdentifier,
            applicationURL: app.bundleURL
        )
        controller.openNewWindow(in: app, tile: tile)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            _ = controller
            print("Last action: \(diagnosticModel.lastAction)")
            print("Failure: \(diagnosticModel.lastFailure ?? "none")")
            exit(diagnosticModel.lastFailure == nil ? 0 : 1)
        }
    }

    private func runSelfTest() {
        var failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        let runningTile = DockTile(
            title: "TextEdit",
            frame: CGRect(x: 100, y: 900, width: 48, height: 48),
            isRunning: true
        )
        let stoppedTile = DockTile(
            title: "Safari",
            frame: CGRect(x: 160, y: 900, width: 48, height: 48),
            isRunning: false
        )
        let policy = DockClickPolicy()
        check(policy.decide(isEnabled: true, tile: runningTile, modifiers: []) == .openNewWindow,
              "plain click on a running app opens a new window")
        check(policy.decide(isEnabled: true, tile: runningTile, modifiers: [.maskShift]) == .passThrough(.modifierKey),
              "shift-click passes through")
        check(policy.decide(isEnabled: true, tile: stoppedTile, modifiers: []) == .passThrough(.applicationNotRunning),
              "click on a stopped app passes through")
        check(ScreenEdgeProximity.isNearEdge(CGPoint(x: 10, y: 500), in: CGRect(x: 0, y: 0, width: 1000, height: 800), band: 220),
              "screen edge proximity catches a bottom Dock edge")
        check(DockSystemApps.isExcluded(DockTile(
            title: "Apps",
            frame: .zero,
            isRunning: true,
            bundleIdentifier: "com.apple.apps.launcher"
        )), "system Dock launchers are excluded")
        check(AltTabSelection.initialIndex(count: 5, reverse: false) == 1,
              "Option-Tab initially selects the previous app")
        check(AltTabSelection.initialIndex(count: 5, reverse: true) == 4,
              "Option-Shift-Tab initially selects the last app")
        check(AltTabSelection.advance(index: 4, count: 5, reverse: false) == 0,
              "switcher wraps forward")
        check(AltTabSelection.advance(index: 0, count: 5, reverse: true) == 4,
              "switcher wraps backward")
        check(AltTabSelection.visibleRange(count: 12, selectedIndex: 8).count == 7,
              "switcher limits the visible row")

        let best = NewWindowMenuScoring.best(in: [
            MenuCandidate(title: "New Tab", keyEquivalent: "t", commandModifiers: 0, enabled: true, hasChildren: false, path: ["File"]),
            MenuCandidate(title: "New Window", keyEquivalent: "n", commandModifiers: 0, enabled: true, hasChildren: false, path: ["File"])
        ])
        check(best?.title == "New Window", "menu matcher prefers New Window over New Tab")

        if let device = MTLCreateSystemDefaultDevice() {
            do {
                let renderer = try OverlayRenderer(device: device)
                check(!renderer.rendererDescription.isEmpty, "Metal renderer builds")
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NewWindowPlz-selftest.png")
                try renderer.writePreview(to: url, pointSize: CGSize(width: 640, height: 420), scale: 1)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                check(size > 1_000, "Metal overlay renders to an image")
                try? FileManager.default.removeItem(at: url)

                var windows = CurrentSpaceWindows.snapshot()
                if windows.count > 7 {
                    windows = Array(windows.prefix(7))
                }
                if windows.isEmpty {
                    check(false, "window switcher has current-Space windows to render")
                } else {
                    renderer.prepareWindowSwitcherCache(for: windows)
                    let switcherURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("NewWindowPlz-switcher-selftest.png")
                    try renderer.writePreview(
                        to: switcherURL,
                        pointSize: CGSize(width: 1280, height: 820),
                        scale: 1,
                        scene: .appSwitcher(AltTabScene(
                            windows: windows,
                            selectedIndex: min(1, windows.count - 1),
                            showSnapshots: false
                        ))
                    )
                    let switcherSize = (try? FileManager.default.attributesOfItem(atPath: switcherURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    check(switcherSize > 1_000, "Metal window switcher renders to an image")
                    try? FileManager.default.removeItem(at: switcherURL)
                }
            } catch {
                check(false, "Metal renderer builds: \(error.localizedDescription)")
            }
        } else {
            check(false, "Metal device is available")
        }

        print(failures == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    private func handleAltTabPreviewIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--alt-tab-preview"),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }

        let outputURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw OverlayRendererError.commandQueue
            }
            let renderer = try OverlayRenderer(device: device)
            var windows = CurrentSpaceWindows.snapshot()
            if windows.count > 7 {
                windows = Array(windows.prefix(7))
            }
            guard !windows.isEmpty else {
                throw OverlayRendererError.previewEncoding
            }
            renderer.prepareWindowSwitcherCache(for: windows)
            let simulateSlide = CommandLine.arguments.contains("--slide") && windows.count >= 6
            let selectedIndex = simulateSlide ? 5 : min(1, windows.count - 1)
            let previousIndex = simulateSlide ? 4 : nil
            let transitionStart = simulateSlide ? (1.35 - 0.13) : nil
            try renderer.writePreview(
                to: outputURL,
                pointSize: CGSize(width: 1280, height: 820),
                scale: 2,
                scene: .appSwitcher(AltTabScene(
                    windows: windows,
                    selectedIndex: selectedIndex,
                    showSnapshots: CommandLine.arguments.contains("--snapshots") || simulateSlide,
                    previousSelectedIndex: previousIndex,
                    selectionTransitionStart: transitionStart
                ))
            )
            print("Wrote Alt-Tab preview to \(outputURL.path)")
            exit(0)
        } catch {
            fputs("Alt-Tab preview failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func handleOverlayPreviewIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--overlay-preview"),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }

        let outputURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw OverlayRendererError.commandQueue
            }
            let renderer = try OverlayRenderer(device: device)
            let pointSize = CGSize(width: 1280, height: 820)
            try renderer.writePreview(to: outputURL, pointSize: pointSize, scale: 2)
            print("Wrote overlay preview to \(outputURL.path)")
            exit(0)
        } catch {
            fputs("Overlay preview failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
