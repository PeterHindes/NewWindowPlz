import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowActivator {
    static func activate(_ window: AltTabWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              !app.isTerminated else {
            return
        }

        DispatchQueue.main.async {
            if app.isHidden {
                app.unhide()
            }
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // Activation may raise the app's last-active window. Correct that by
        // raising the exact AX window after the activation transaction.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.03) {
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

            if let target = exactMatch ?? titleMatch {
                AXUIElementSetAttributeValue(
                    target,
                    kAXMainAttribute as CFString,
                    kCFBooleanTrue
                )
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            }
        }
    }
}
