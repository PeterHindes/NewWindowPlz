import AppKit
import Metal
import QuartzCore

final class OverlayHost {
    private let model: AppModel
    private var panel: OverlayPanel?
    private var metalView: MetalOverlayView?
    private var renderer: OverlayRenderer?
    private var hideWorkItem: DispatchWorkItem?
    private var warmupWorkItem: DispatchWorkItem?
    private var warmupFinishWorkItem: DispatchWorkItem?
    private var pendingSwitcherWindows: [AltTabWindow]?
    private var showStartedAt: CFTimeInterval = 0
    private var currentScreenNumber: NSNumber?
    private var isVisible = false

    private(set) var isReady = false

    init(model: AppModel) {
        self.model = model
    }

    deinit {
        hideWorkItem?.cancel()
        warmupWorkItem?.cancel()
        warmupFinishWorkItem?.cancel()
        metalView?.stopAnimating()
    }

    func prepare() {
        guard !isReady else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            let message = "No Metal device is available."
            model.overlayReadiness = .unavailable(message)
            model.lastFailure = message
            Log.overlay.error("\(message, privacy: .public)")
            return
        }

        do {
            let renderer = try OverlayRenderer(device: device)
            let screen = NSScreen.main ?? NSScreen.screens.first
            let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
            let view = MetalOverlayView(frame: NSRect(origin: .zero, size: frame.size), device: device)
            view.renderer = renderer

            let panel = OverlayPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.contentView = view
            panel.alphaValue = 0

            self.renderer = renderer
            self.metalView = view
            self.panel = panel
            self.currentScreenNumber = Self.screenNumber(screen)
            isReady = true

            if let pendingSwitcherWindows {
                renderer.prepareWindowSwitcherCache(for: pendingSwitcherWindows)
                self.pendingSwitcherWindows = nil
            }

            let refreshRate = Self.refreshRate(for: screen)
            model.overlayReadiness = .ready(refreshRate: refreshRate)
            model.overlayRendererDescription = renderer.rendererDescription
            Log.overlay.info("Overlay prepared: \(renderer.rendererDescription, privacy: .public)")

            scheduleWarmup()
        } catch {
            isReady = false
            model.overlayReadiness = .unavailable(error.localizedDescription)
            model.lastFailure = "Overlay renderer: \(error.localizedDescription)"
            Log.overlay.error("Overlay setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func prepareWindowSwitcherCache(windows: [AltTabWindow]) {
        pendingSwitcherWindows = windows
        renderer?.prepareWindowSwitcherCache(for: windows)
    }

    func showDemo(autoHideAfter duration: TimeInterval? = 4.0) {
        if !isReady {
            prepare()
        }
        guard let view = metalView else { return }
        view.scene = .demo
        reveal(autoHideAfter: duration)
    }

    @discardableResult
    func showWindowSwitcher(windows: [AltTabWindow],
                            selectedIndex: Int,
                            showSnapshots: Bool) -> Bool {
        if !isReady {
            prepare()
        }
        guard isReady, let view = metalView else { return false }
        renderer?.prepareWindowSwitcherCache(for: windows)
        view.scene = .appSwitcher(AltTabScene(
            windows: windows,
            selectedIndex: selectedIndex,
            showSnapshots: showSnapshots
        ))
        reveal(autoHideAfter: nil)
        return true
    }

    func updateWindowSwitcher(windows: [AltTabWindow],
                              selectedIndex: Int,
                              showSnapshots: Bool) {
        guard isVisible, let view = metalView, !windows.isEmpty else { return }
        renderer?.prepareWindowSwitcherCache(for: windows)
        view.scene = .appSwitcher(AltTabScene(
            windows: windows,
            selectedIndex: min(max(0, selectedIndex), windows.count - 1),
            showSnapshots: showSnapshots
        ))
        view.renderImmediately()
    }

    func updateWindowSwitcherSelection(_ selectedIndex: Int, previousIndex: Int?) {
        guard isVisible, let view = metalView else { return }
        guard case .appSwitcher(var scene) = view.scene else { return }
        scene.previousSelectedIndex = previousIndex
        scene.selectionTransitionStart = CACurrentMediaTime()
        scene.selectedIndex = selectedIndex
        view.scene = .appSwitcher(scene)
        view.renderImmediately()
    }

    func updateWindowSnapshot(windowID: CGWindowID, image: CGImage) {
        renderer?.cacheWindowSnapshot(windowID: windowID, image: image)
        guard isVisible, let view = metalView else { return }
        guard case .appSwitcher(let scene) = view.scene,
              scene.windows.contains(where: { $0.windowID == windowID }) else {
            return
        }
        view.renderImmediately()
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        warmupWorkItem?.cancel()
        warmupFinishWorkItem?.cancel()
        isVisible = false
        panel?.alphaValue = 0
        metalView?.pauseAnimating()
    }

    private func reveal(autoHideAfter duration: TimeInterval?) {
        guard let panel, let view = metalView, let renderer = renderer else { return }

        warmupWorkItem?.cancel()
        warmupFinishWorkItem?.cancel()
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let screen = screenUnderMouse() ?? NSScreen.main
        let screenNumber = Self.screenNumber(screen)
        let screenChanged = screenNumber != currentScreenNumber
        if screenChanged, let screen {
            view.stopAnimating()
            panel.setFrame(screen.frame, display: false)
            view.updateDrawableSize()
            currentScreenNumber = screenNumber
        }

        // The panel normally remains ordered-in at alpha 0. This branch only
        // runs if WindowServer dropped it (for example after a display change).
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        view.onFirstFrame = { [weak self] in
            guard let self, self.isVisible else { return }
            self.model.overlayFirstFrameMicroseconds = (CACurrentMediaTime() - self.showStartedAt) * 1_000_000
        }

        let wasVisible = isVisible
        let start = CACurrentMediaTime()
        showStartedAt = start
        view.sceneStartTime = start
        isVisible = true
        panel.alphaValue = 1
        view.resumeAnimating()
        view.renderImmediately()

        if !wasVisible {
            let elapsed = (CACurrentMediaTime() - start) * 1_000_000
            model.overlayOpenMicroseconds = elapsed
            model.overlayRendererDescription = renderer.rendererDescription
            Log.overlay.debug("Overlay reveal took \(elapsed, privacy: .public) µs")
        }

        guard let duration else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func scheduleWarmup() {
        warmupWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.warmup()
        }
        warmupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func warmup() {
        guard !isVisible, let panel, let view = metalView else { return }
        let screen = NSScreen.main
        if let screen {
            panel.setFrame(screen.frame, display: false)
            currentScreenNumber = Self.screenNumber(screen)
        }
        view.scene = .demo
        view.sceneStartTime = CACurrentMediaTime()
        view.updateDrawableSize()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        view.resumeAnimating()
        view.renderImmediately()

        let finish = DispatchWorkItem { [weak self] in
            guard let self, !self.isVisible else { return }
            self.metalView?.pauseAnimating()
            self.panel?.alphaValue = 0
            Log.overlay.debug("Overlay prewarm complete; surface remains resident at alpha 0.")
        }
        warmupFinishWorkItem?.cancel()
        warmupFinishWorkItem = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: finish)
    }

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    private static func screenNumber(_ screen: NSScreen?) -> NSNumber? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private static func refreshRate(for screen: NSScreen?) -> Double {
        guard let screen,
              let number = screenNumber(screen),
              let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)) else {
            return 60
        }
        return mode.refreshRate > 0 ? mode.refreshRate : 60
    }
}
