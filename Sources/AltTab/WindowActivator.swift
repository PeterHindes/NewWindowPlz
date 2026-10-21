import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

private struct ProcessSerialNumber {
    var highLongOfPSN: UInt32 = 0
    var lowLongOfPSN: UInt32 = 0
}

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum WindowActivator {
    private enum SkyLight {
        typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> CGError
        typealias PostEventRecord = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> CGError

        private static let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        )
        private static let setFrontProcess: SetFrontProcess? = {
            guard let handle, let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else {
                return nil
            }
            return unsafeBitCast(symbol, to: SetFrontProcess.self)
        }()
        private static let postEventRecord: PostEventRecord? = {
            guard let handle, let symbol = dlsym(handle, "SLPSPostEventRecordTo") else {
                return nil
            }
            return unsafeBitCast(symbol, to: PostEventRecord.self)
        }()

        static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
            guard let setFrontProcess, let postEventRecord else { return false }

            var psn = ProcessSerialNumber()
            guard GetProcessForPID(pid, &psn) == 0 else { return false }

            let frontResult = withUnsafeMutablePointer(to: &psn) { pointer in
                setFrontProcess(
                    UnsafeMutableRawPointer(pointer),
                    windowID,
                    0x200 // SLPSMode.userGenerated
                )
            }
            guard frontResult == .success else { return false }

            var bytes = [UInt8](repeating: 0, count: 0x100)
            bytes[0x04] = 0xF8
            bytes[0x3A] = 0x10
            var wideWindowID = UInt32(windowID)
            memcpy(&bytes[0x3C], &wideWindowID, MemoryLayout<UInt32>.size)
            var point = CGPoint(x: -1, y: -1)
            memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
            bytes[0x08] = 0x01
            _ = withUnsafeMutablePointer(to: &psn) {
                postEventRecord(UnsafeMutableRawPointer($0), &bytes)
            }
            bytes[0x08] = 0x02
            _ = withUnsafeMutablePointer(to: &psn) {
                postEventRecord(UnsafeMutableRawPointer($0), &bytes)
            }
            return true
        }
    }

    static func activate(_ window: AltTabWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              !app.isTerminated else {
            return
        }

        let preciseFocus = SkyLight.focus(windowID: window.windowID, pid: window.pid)
        if !preciseFocus && app.isHidden {
            app.unhide()
        }

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.02) {
            let raised = raiseAXWindow(window)
            if !preciseFocus && !raised {
                // Last resort: standard app activation. This can bring the
                // app's other windows forward, so it is used only when both
                // precise window-focus paths failed.
                DispatchQueue.main.async {
                    if app.isHidden {
                        app.unhide()
                    }
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
    }

    @discardableResult
    private static func raiseAXWindow(_ window: AltTabWindow) -> Bool {
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let axWindows = AX.elements(appElement, "AXWindows")

        var exactMatch: AXUIElement?
        var titleMatch: AXUIElement?
        for axWindow in axWindows {
            var candidateID: CGWindowID = 0
            if AXUIElementGetWindow(axWindow, &candidateID) == .success,
               candidateID == window.windowID {
                exactMatch = axWindow
                break
            }
            if titleMatch == nil,
               !window.windowTitle.isEmpty,
               AX.string(axWindow, kAXTitleAttribute as String) == window.windowTitle {
                titleMatch = axWindow
            }
        }

        guard let target = exactMatch ?? titleMatch else { return false }
        AXUIElementSetAttributeValue(
            target,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        return AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success
    }
}
