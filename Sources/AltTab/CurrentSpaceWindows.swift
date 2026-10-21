import AppKit
import CoreGraphics
import Foundation

enum CurrentSpaceWindows {
    /// CGWindowList with `.optionOnScreenOnly` returns the windows composited
    /// in the active Space(s), which is exactly the scope requested for the
    /// window switcher. Minimized and other-Space windows are excluded.
    static func snapshot() -> [AltTabWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let appsByPID = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map {
                ($0.processIdentifier, $0)
            }
        )

        var seen = Set<CGWindowID>()
        var result: [AltTabWindow] = []

        for raw in rawList {
            guard let layer = raw[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidValue = raw[kCGWindowOwnerPID as String] as? Int,
                  let windowNumber = raw[kCGWindowNumber as String] as? Int,
                  let alpha = raw[kCGWindowAlpha as String] as? Double, alpha > 0.05,
                  let boundsDictionary = raw[kCGWindowBounds as String] as? [String: Any],
                  let width = boundsDictionary["Width"] as? Double,
                  let height = boundsDictionary["Height"] as? Double,
                  width >= 60, height >= 60 else {
                continue
            }

            let pid = pid_t(pidValue)
            guard pid != ownPID,
                  let app = appsByPID[pid],
                  app.activationPolicy == .regular,
                  app.bundleIdentifier != ownBundleIdentifier,
                  let appName = app.localizedName,
                  !appName.isEmpty else {
                continue
            }

            let isOnscreen = raw[kCGWindowIsOnscreen as String] as? Bool ?? true
            guard isOnscreen else { continue }

            let windowID = CGWindowID(windowNumber)
            guard !seen.contains(windowID) else { continue }
            seen.insert(windowID)

            let title = (raw[kCGWindowName as String] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            result.append(AltTabWindow(
                windowID: windowID,
                pid: pid,
                bundleIdentifier: app.bundleIdentifier ?? "",
                appName: appName,
                windowTitle: title,
                isHidden: app.isHidden
            ))
        }

        return result
    }
}
