import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class AltTabEventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var tapThread: Thread?
    private var swallowedKeys = Set<CGKeyCode>()
    private(set) var isRunning = false
    private(set) var isActive = false

    var onBegin: ((_ reverse: Bool) -> Void)?
    var onAdvance: ((_ reverse: Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onPreviousSpace: (() -> Void)?

    private enum KeyCode {
        static let tab: CGKeyCode = 0x30
        static let escape: CGKeyCode = 0x35
        static let returnKey: CGKeyCode = 0x24
        static let keypadEnter: CGKeyCode = 0x4C
        static let leftArrow: CGKeyCode = 0x7B
        static let rightArrow: CGKeyCode = 0x7C
        static let downArrow: CGKeyCode = 0x7D
        static let upArrow: CGKeyCode = 0x7E
        static let backtick: CGKeyCode = 0x32
        static let backtickISO: CGKeyCode = 0x0A
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue |
            CGEventMask(1) << CGEventType.keyUp.rawValue |
            CGEventMask(1) << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.action.error("Alt-Tab event tap could not be created.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap
        self.source = source
        swallowedKeys.removeAll()
        isActive = false

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let source = self.source else { return }
            let currentRunLoop = CFRunLoopGetCurrent()
            self.runLoop = currentRunLoop
            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "NewWindowPlz Alt-Tab Event Tap"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        tapThread = thread
        thread.start()

        if ready.wait(timeout: .now() + 1.0) == .timedOut {
            Log.action.error("Alt-Tab event tap thread did not become ready.")
            stop()
            return false
        }

        isRunning = true
        Log.action.info("Alt-Tab event tap started.")
        return true
    }

    func stop() {
        guard isRunning || tap != nil else { return }

        if isActive {
            isActive = false
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
        }
        swallowedKeys.removeAll()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }

        tap = nil
        source = nil
        runLoop = nil
        tapThread = nil
        isRunning = false
        Log.action.info("Alt-Tab event tap stopped.")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isActive {
                isActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onCancel?()
                }
            }
            swallowedKeys.removeAll()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.action.error("Alt-Tab event tap disabled by the system; re-enabled.")
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            if isActive && !event.flags.contains(.maskAlternate) {
                isActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onCommit?()
                }
            }
            // Pass modifier changes through: the focused app saw Option go
            // down before the switcher opened, so it must see it go up too.
            return Unmanaged.passUnretained(event)

        case .keyDown:
            return handleKeyDown(event: event)

        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if swallowedKeys.remove(keyCode) != nil {
                return nil
            }
            return isActive ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let optionHeld = flags.contains(.maskAlternate)

        if keyCode == KeyCode.tab, optionHeld {
            let reverse = flags.contains(.maskShift)
            if isActive {
                DispatchQueue.main.async { [weak self] in
                    self?.onAdvance?(reverse)
                }
            } else {
                isActive = true
                DispatchQueue.main.async { [weak self] in
                    self?.onBegin?(reverse)
                }
            }
            swallowedKeys.insert(keyCode)
            return nil
        }

        if !isActive, (keyCode == KeyCode.backtick || keyCode == KeyCode.backtickISO), optionHeld {
            DispatchQueue.main.async { [weak self] in
                self?.onPreviousSpace?()
            }
            swallowedKeys.insert(keyCode)
            return nil
        }

        guard isActive else {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCode.escape {
            isActive = false
            swallowedKeys.insert(keyCode)
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return nil
        }

        if keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter {
            isActive = false
            swallowedKeys.insert(keyCode)
            DispatchQueue.main.async { [weak self] in
                self?.onCommit?()
            }
            return nil
        }

        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.upArrow {
            DispatchQueue.main.async { [weak self] in
                self?.onAdvance?(true)
            }
            swallowedKeys.insert(keyCode)
            return nil
        }

        if keyCode == KeyCode.rightArrow || keyCode == KeyCode.downArrow {
            DispatchQueue.main.async { [weak self] in
                self?.onAdvance?(false)
            }
            swallowedKeys.insert(keyCode)
            return nil
        }

        // While the switcher is modal, don't leak keystrokes into the app
        // underneath.
        swallowedKeys.insert(keyCode)
        return nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let eventTap = Unmanaged<AltTabEventTap>.fromOpaque(refcon).takeUnretainedValue()
        return eventTap.handle(type: type, event: event)
    }
}
