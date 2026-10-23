import AppKit
import CoreGraphics
import Foundation

enum SpaceSwitchPlan {
    static func steps(fromIndex: Int, toIndex: Int) -> Int {
        toIndex - fromIndex
    }
}

final class SpaceController {
    private struct DisplayState {
        var current: UInt64
        var previous: UInt64?
    }

    private var states: [String: DisplayState] = [:]
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private let switchQueue = DispatchQueue(label: "com.peter.newwindowplz.space-switch", qos: .userInteractive)
    private var isSwitching = false
    var onFailure: ((String) -> Void)?

    func start() {
        guard timer == nil else { return }
        refreshHistory()

        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.refreshHistory()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.refreshHistory()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        states.removeAll()
    }

    /// Call immediately before activating an app or window that may make
    /// macOS jump to another Space. This preserves the current Space as the
    /// return target even if the user presses ⌥` before the next poll.
    func noteSpaceBeforeActivation() {
        guard !isSwitching else { return }
        let displays = SpaceMetadata.displays()
        guard !displays.isEmpty else { return }
        let screen = screenUnderMouse()
        let screenIdentifier = SpaceMetadata.displayIdentifier(for: screen)
        let display = displays.first {
            $0.identifier.caseInsensitiveCompare(screenIdentifier ?? "") == .orderedSame
        } ?? displays.first!
        states[display.identifier] = DisplayState(
            current: display.currentSpaceID,
            previous: display.currentSpaceID
        )
    }

    func switchToPreviousSpace() {
        guard !isSwitching else { return }
        refreshHistory()

        let displays = SpaceMetadata.displays()
        guard !displays.isEmpty else {
            Log.action.error("No managed displays available for Space switching.")
            return
        }

        let screen = screenUnderMouse()
        let screenIdentifier = SpaceMetadata.displayIdentifier(for: screen)
        let display = displays.first {
            $0.identifier.caseInsensitiveCompare(screenIdentifier ?? "") == .orderedSame
        } ?? displays.first!

        let state = states[display.identifier]
        let currentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID })
        var targetID = state?.previous

        // If history is empty (for example immediately after launch), use the
        // adjacent Space as a sensible fallback so the command remains useful.
        if targetID == nil || targetID == display.currentSpaceID,
           let currentIndex {
            if currentIndex > 0 {
                targetID = display.spaces[currentIndex - 1].id
            } else if display.spaces.count > 1 {
                targetID = display.spaces[currentIndex + 1].id
            }
        }

        guard let targetID,
              targetID != display.currentSpaceID,
              currentIndex != nil,
              let targetIndex = display.spaces.firstIndex(where: { $0.id == targetID }),
              targetIndex != currentIndex else {
            Log.action.debug("No previous Space to return to.")
            return
        }

        let sourceID = display.currentSpaceID
        let goRight = targetIndex > currentIndex!
        let stepCount = abs(targetIndex - currentIndex!)
        isSwitching = true
        Log.action.info("Returning to previous Space: \(sourceID, privacy: .public) → \(targetID, privacy: .public), steps=\(stepCount, privacy: .public)")

        switchQueue.async { [weak self] in
            guard let self else { return }

            let posted = SpaceSwipeGesture.post(steps: stepCount, goRight: goRight)
            Thread.sleep(forTimeInterval: 0.30)

            let finalDisplay = SpaceMetadata.displays().first {
                $0.identifier.caseInsensitiveCompare(display.identifier) == .orderedSame
            }
            let finalID = finalDisplay?.currentSpaceID

            DispatchQueue.main.async {
                self.isSwitching = false
                if let finalID {
                    self.states[display.identifier] = DisplayState(
                        current: finalID,
                        previous: sourceID
                    )
                }
                if posted, finalID == targetID {
                    Log.action.info("Returned to previous Space \(targetID, privacy: .public)")
                } else {
                    Log.action.error("Space swipe failed; current=\(finalID ?? 0, privacy: .public) target=\(targetID, privacy: .public)")
                    self.onFailure?("Couldn’t switch Spaces. Enable a trackpad Space-swipe gesture and try again.")
                }
            }
        }
    }

    private func refreshHistory() {
        guard !isSwitching else { return }
        let displays = SpaceMetadata.displays()
        guard !displays.isEmpty else { return }

        var liveIdentifiers = Set<String>()
        for display in displays {
            liveIdentifiers.insert(display.identifier)
            if let old = states[display.identifier] {
                if old.current != display.currentSpaceID {
                    states[display.identifier] = DisplayState(
                        current: display.currentSpaceID,
                        previous: old.current
                    )
                }
            } else {
                states[display.identifier] = DisplayState(
                    current: display.currentSpaceID,
                    previous: nil
                )
            }
        }

        states = states.filter { liveIdentifiers.contains($0.key) }
    }

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}
