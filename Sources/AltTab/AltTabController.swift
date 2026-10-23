import AppKit
import Foundation

final class AltTabController {
    private let overlayHost: OverlayHost
    private let model: AppModel
    private let settings: AppSettings
    private let eventTap = AltTabEventTap()
    private let snapshotService = WindowSnapshotService()
    private let spaceController = SpaceController()

    private let catalogQueue = DispatchQueue(label: "com.peter.newwindowplz.window-catalog", qos: .userInitiated)
    private var cachedWindows: [AltTabWindow] = []
    private var windows: [AltTabWindow] = []
    private var selectedIndex = 0
    private var lastActivatedWindow: AltTabWindow?
    private var lastActivatedAt: CFTimeInterval = 0
    private var isPresenting = false
    private var isScanningCatalog = false
    private var scanAgain = false
    private var refreshOpenOverlayWhenScanFinishes = false
    private var previewWorkItem: DispatchWorkItem?
    private var contentRetryWorkItem: DispatchWorkItem?
    private var contentRetryCount = 0
    private var catalogTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localObservers: [NSObjectProtocol] = []

    init(overlayHost: OverlayHost, model: AppModel, settings: AppSettings) {
        self.overlayHost = overlayHost
        self.model = model
        self.settings = settings

        eventTap.onBegin = { [weak self] reverse in
            self?.begin(reverse: reverse)
        }
        eventTap.onAdvance = { [weak self] reverse in
            self?.advance(reverse: reverse)
        }
        eventTap.onCommit = { [weak self] in
            self?.commit()
        }
        eventTap.onCancel = { [weak self] in
            self?.cancel()
        }
        eventTap.onPreviousSpace = { [weak self] in
            self?.spaceController.switchToPreviousSpace()
        }
        spaceController.onFailure = { [weak self] message in
            self?.model.lastFailure = message
        }

        snapshotService.onImage = { [weak self] windowID, image in
            self?.overlayHost.updateWindowSnapshot(windowID: windowID, image: image)
        }
    }

    deinit {
        stop()
    }

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard settings.altTabEnabled, AccessibilityPermission.isGranted else {
            model.altTabActive = false
            return
        }

        guard eventTap.start() else {
            model.altTabActive = false
            model.lastFailure = "The Option-Tab event tap could not be created."
            return
        }

        isRunning = true
        model.altTabActive = true
        spaceController.start()
        installObservers()
        startCatalogTimer()
        scheduleContentPreparation()
        Log.action.info("Window switcher started.")
    }

    func stop() {
        guard isRunning || eventTap.isRunning else {
            model.altTabActive = false
            return
        }
        isRunning = false
        previewWorkItem?.cancel()
        previewWorkItem = nil
        contentRetryWorkItem?.cancel()
        contentRetryWorkItem = nil
        catalogTimer?.invalidate()
        catalogTimer = nil
        removeObservers()
        spaceController.stop()
        eventTap.stop()
        if isPresenting {
            isPresenting = false
            overlayHost.hide()
        }
        model.altTabActive = false
        Log.action.info("Window switcher stopped.")
    }

    func noteCurrentSpaceBeforeActivation() {
        spaceController.noteSpaceBeforeActivation()
    }

    func returnToPreviousSpace() {
        spaceController.switchToPreviousSpace()
    }

    func scheduleContentPreparation() {
        guard isRunning else { return }
        guard overlayHost.isReady else {
            contentRetryWorkItem?.cancel()
            guard contentRetryCount < 20 else { return }
            contentRetryCount += 1
            let work = DispatchWorkItem { [weak self] in
                self?.scheduleContentPreparation()
            }
            contentRetryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }

        contentRetryCount = 0
        refreshWindowCatalog(updateOpenOverlay: false)
    }

    func preview() {
        guard overlayHost.isReady else { return }
        if isPresenting {
            cancel()
        }
        previewWorkItem?.cancel()

        let start = CACurrentMediaTime()
        let availableWindows = windowsForImmediatePresentation()
        guard !availableWindows.isEmpty else { return }
        windows = availableWindows
        overlayHost.prepareWindowSwitcherCache(windows: windows)
        selectedIndex = AltTabSelection.initialIndex(count: windows.count, reverse: false)
        skipCurrentWindowIfNeeded(reverse: false)
        guard overlayHost.showWindowSwitcher(
            windows: windows,
            selectedIndex: selectedIndex,
            showSnapshots: snapshotsEnabled
        ) else {
            return
        }
        isPresenting = true
        model.switcherOpenMicroseconds = (CACurrentMediaTime() - start) * 1_000_000
        requestSnapshotsForVisibleWindows(force: true)
        refreshWindowCatalog(updateOpenOverlay: true)

        let work = DispatchWorkItem { [weak self] in
            self?.cancel()
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func begin(reverse: Bool) {
        guard !isPresenting else { return }
        previewWorkItem?.cancel()
        previewWorkItem = nil

        let start = CACurrentMediaTime()
        let availableWindows = windowsForImmediatePresentation()
        guard !availableWindows.isEmpty else { return }
        windows = availableWindows
        overlayHost.prepareWindowSwitcherCache(windows: windows)
        selectedIndex = AltTabSelection.initialIndex(count: windows.count, reverse: reverse)
        skipCurrentWindowIfNeeded(reverse: reverse)
        guard overlayHost.showWindowSwitcher(
            windows: windows,
            selectedIndex: selectedIndex,
            showSnapshots: snapshotsEnabled
        ) else {
            return
        }
        isPresenting = true
        model.altTabWindowCount = windows.count
        model.switcherOpenMicroseconds = (CACurrentMediaTime() - start) * 1_000_000
        requestSnapshotsForVisibleWindows(force: true)
        refreshWindowCatalog(updateOpenOverlay: true)

        Log.action.debug("Window switcher opened with \(self.windows.count, privacy: .public) current-Space windows")
    }

    private func advance(reverse: Bool) {
        guard isPresenting, windows.count > 1 else { return }
        let previousIndex = selectedIndex
        selectedIndex = AltTabSelection.advance(
            index: selectedIndex,
            count: windows.count,
            reverse: reverse
        )
        overlayHost.updateWindowSwitcherSelection(selectedIndex, previousIndex: previousIndex)
        requestSnapshotsForVisibleWindows(force: false)
    }

    private func commit() {
        guard isPresenting else { return }
        isPresenting = false
        refreshOpenOverlayWhenScanFinishes = false
        previewWorkItem?.cancel()
        previewWorkItem = nil
        overlayHost.hide()

        guard windows.indices.contains(selectedIndex) else { return }
        let selected = windows[selectedIndex]
        lastActivatedWindow = selected
        lastActivatedAt = CACurrentMediaTime()
        promoteRecentActivationIfNeeded(in: &cachedWindows)
        WindowActivator.activate(selected)
        model.lastAction = "Switched to \(selected.displayTitle)"
        Log.action.info("Window switcher activated \(selected.displayTitle, privacy: .public)")
    }

    private func cancel() {
        guard isPresenting else { return }
        isPresenting = false
        refreshOpenOverlayWhenScanFinishes = false
        previewWorkItem?.cancel()
        previewWorkItem = nil
        overlayHost.hide()
    }

    private var snapshotsEnabled: Bool {
        settings.showWindowSnapshots && model.screenCaptureGranted
    }

    private var visibleWindowLimit: Int {
        snapshotsEnabled ? AltTabLayout.snapshotVisibleLimit : AltTabLayout.iconVisibleLimit
    }

    private func requestSnapshotsForVisibleWindows(force: Bool) {
        guard snapshotsEnabled, !windows.isEmpty else { return }
        let range = AltTabSelection.visibleRange(
            count: windows.count,
            selectedIndex: selectedIndex,
            maxVisible: visibleWindowLimit
        )
        for index in range where windows.indices.contains(index) {
            snapshotService.request(windowID: windows[index].windowID, force: force)
        }
    }

    /// The normal path is a pure cache read. The synchronous scan is only a
    /// first-use fallback before the background catalog has been populated.
    private func windowsForImmediatePresentation() -> [AltTabWindow] {
        if cachedWindows.isEmpty {
            cachedWindows = CurrentSpaceWindows.snapshot()
            overlayHost.prepareWindowSwitcherCache(windows: cachedWindows)
            model.altTabWindowCount = cachedWindows.count
        }
        promoteRecentActivationIfNeeded(in: &cachedWindows)
        return cachedWindows
    }

    private func skipCurrentWindowIfNeeded(reverse: Bool) {
        guard windows.count > 1,
              let recent = lastActivatedWindow,
              CACurrentMediaTime() - lastActivatedAt < 1.25,
              windows.indices.contains(selectedIndex),
              windows[selectedIndex].windowID == recent.windowID else {
            return
        }
        selectedIndex = AltTabSelection.advance(
            index: selectedIndex,
            count: windows.count,
            reverse: reverse
        )
    }

    private func promoteRecentActivationIfNeeded(in windows: inout [AltTabWindow]) {
        guard let recent = lastActivatedWindow,
              CACurrentMediaTime() - lastActivatedAt < 1.25 else {
            return
        }
        guard let index = windows.firstIndex(where: { $0.windowID == recent.windowID }) else {
            return
        }
        guard index != 0 else { return }
        let window = windows.remove(at: index)
        windows.insert(window, at: 0)
    }

    private func refreshWindowCatalog(updateOpenOverlay: Bool) {
        guard isRunning else { return }
        if isScanningCatalog {
            scanAgain = true
            refreshOpenOverlayWhenScanFinishes = refreshOpenOverlayWhenScanFinishes || updateOpenOverlay
            return
        }

        isScanningCatalog = true
        let shouldUpdateOpenOverlay = updateOpenOverlay || refreshOpenOverlayWhenScanFinishes
        catalogQueue.async { [weak self] in
            guard let self else { return }
            let scanned = CurrentSpaceWindows.snapshot()
            DispatchQueue.main.async {
                guard self.isRunning else {
                    self.isScanningCatalog = false
                    return
                }
                self.isScanningCatalog = false
                self.applyCatalog(scanned, updateOpenOverlay: shouldUpdateOpenOverlay)
                if !self.scanAgain {
                    self.refreshOpenOverlayWhenScanFinishes = false
                }

                if self.scanAgain {
                    self.scanAgain = false
                    self.refreshOpenOverlayWhenScanFinishes = false
                    self.refreshWindowCatalog(updateOpenOverlay: true)
                }
            }
        }
    }

    private func applyCatalog(_ scanned: [AltTabWindow], updateOpenOverlay: Bool) {
        var adjusted = scanned
        promoteRecentActivationIfNeeded(in: &adjusted)
        cachedWindows = adjusted
        overlayHost.prepareWindowSwitcherCache(windows: adjusted)
        model.altTabWindowCount = adjusted.count

        guard updateOpenOverlay, isPresenting else { return }
        let selectedWindowID = windows.indices.contains(selectedIndex)
            ? windows[selectedIndex].windowID
            : nil

        guard !adjusted.isEmpty else {
            cancel()
            return
        }

        windows = adjusted
        if let selectedWindowID,
           let newIndex = adjusted.firstIndex(where: { $0.windowID == selectedWindowID }) {
            selectedIndex = newIndex
        } else {
            selectedIndex = min(selectedIndex, adjusted.count - 1)
        }

        overlayHost.updateWindowSwitcher(
            windows: windows,
            selectedIndex: selectedIndex,
            showSnapshots: snapshotsEnabled
        )
        requestSnapshotsForVisibleWindows(force: false)
    }

    private func startCatalogTimer() {
        catalogTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshWindowCatalog(updateOpenOverlay: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        catalogTimer = timer
    }

    private func installObservers() {
        removeObservers()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in workspaceNames {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                   app.processIdentifier != self.lastActivatedWindow?.pid {
                    self.lastActivatedWindow = nil
                }
                self.refreshWindowCatalog(updateOpenOverlay: true)
            }
            workspaceObservers.append(token)
        }

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindowCatalog(updateOpenOverlay: false)
        }
        localObservers.append(screenToken)
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        localObservers.forEach { NotificationCenter.default.removeObserver($0) }
        localObservers.removeAll()
    }
}
