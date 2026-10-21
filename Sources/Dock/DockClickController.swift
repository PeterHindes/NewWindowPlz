import AppKit
import Foundation

final class DockClickController {
    private let inspector: DockInspector
    private let geometryCache: DockGeometryCache
    private let eventTap: DockEventTap
    private let newWindowController: NewWindowController
    private let model: AppModel
    private let settings: AppSettings

    private let scanQueue = DispatchQueue(label: "com.peter.newwindowplz.dock-scan", qos: .utility)
    private var scanTimer: DispatchSourceTimer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private(set) var isMonitoring = false

    init(inspector: DockInspector,
         geometryCache: DockGeometryCache,
         eventTap: DockEventTap,
         newWindowController: NewWindowController,
         model: AppModel,
         settings: AppSettings) {
        self.inspector = inspector
        self.geometryCache = geometryCache
        self.eventTap = eventTap
        self.newWindowController = newWindowController
        self.model = model
        self.settings = settings

        eventTap.onOpenNewWindow = { [weak self] tile, pid in
            self?.handleNewWindow(tile: tile, pid: pid)
        }
        eventTap.onTapRecovered = { [weak self] in
            DispatchQueue.main.async {
                self?.model.eventTapDescription = "Event tap recovered"
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isMonitoring else { return true }
        guard settings.monitoringEnabled else {
            DispatchQueue.main.async {
                self.model.monitoringActive = false
                self.model.eventTapDescription = "Paused"
            }
            return false
        }
        guard AccessibilityPermission.isGranted else {
            DispatchQueue.main.async {
                self.model.monitoringActive = false
                self.model.eventTapDescription = "Waiting for Accessibility permission"
            }
            return false
        }

        geometryCache.clear()
        guard eventTap.start() else {
            DispatchQueue.main.async {
                self.model.monitoringActive = false
                self.model.eventTapDescription = "Could not start event tap"
                self.model.lastFailure = "The Dock event tap could not be created. Check Accessibility permission and relaunch the app."
            }
            return false
        }

        isMonitoring = true
        installObservers()
        startScanTimer()
        refreshNow()

        DispatchQueue.main.async {
            self.model.monitoringActive = true
            self.model.eventTapDescription = "Monitoring Dock clicks"
            self.model.lastFailure = nil
        }
        return true
    }

    func stop() {
        guard isMonitoring else {
            DispatchQueue.main.async {
                self.model.monitoringActive = false
            }
            return
        }

        isMonitoring = false
        scanTimer?.cancel()
        scanTimer = nil
        removeObservers()
        eventTap.stop()
        geometryCache.clear()

        DispatchQueue.main.async {
            self.model.monitoringActive = false
            self.model.eventTapDescription = "Paused"
            self.model.cachedDockTileCount = 0
        }
    }

    func refreshNow() {
        guard isMonitoring else { return }
        scanQueue.async { [weak self] in
            guard let self, self.isMonitoring else { return }
            let snapshot = self.inspector.scan()
            self.geometryCache.update(snapshot)
            let count = snapshot.tiles.count
            DispatchQueue.main.async {
                self.model.cachedDockTileCount = count
            }
        }
    }

    func invalidateDock() {
        inspector.invalidateDockElement()
        refreshNow()
    }

    private func startScanTimer() {
        scanTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: scanQueue)
        timer.schedule(deadline: .now() + 1.5,
                       repeating: 1.5,
                       leeway: .milliseconds(350))
        timer.setEventHandler { [weak self] in
            guard let self, self.isMonitoring else { return }
            let snapshot = self.inspector.scan()
            self.geometryCache.update(snapshot)
            let count = snapshot.tiles.count
            DispatchQueue.main.async {
                self.model.cachedDockTileCount = count
            }
        }
        timer.resume()
        scanTimer = timer
    }

    private func installObservers() {
        removeObservers()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in workspaceNames {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if name == NSWorkspace.didTerminateApplicationNotification {
                        self.newWindowController.forget(pid: app.processIdentifier)
                    }
                    if name == NSWorkspace.didLaunchApplicationNotification,
                       app.bundleIdentifier == "com.apple.dock" {
                        self.invalidateDock()
                    }
                }
                self.refreshNow()
            }
            workspaceObservers.append(token)
        }

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNow()
        }
        localObservers.append(screenToken)

        let dockPrefToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateDock()
        }
        distributedObservers.append(dockPrefToken)
    }

    private func removeObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        localObservers.forEach { NotificationCenter.default.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.removeAll()
        localObservers.removeAll()
        distributedObservers.removeAll()
    }

    private func handleNewWindow(tile: DockTile, pid: pid_t) {
        guard let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated else {
            Log.dock.error("Running application disappeared before action: \(tile.title, privacy: .public)")
            return
        }
        newWindowController.openNewWindow(in: application, tile: tile)
    }
}
