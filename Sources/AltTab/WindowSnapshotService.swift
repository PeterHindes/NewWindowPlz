import AppKit
import CoreGraphics
import Foundation
import QuartzCore

enum ScreenCapturePermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

final class WindowSnapshotService {
    var onImage: ((CGWindowID, CGImage) -> Void)?

    private let queue = DispatchQueue(label: "com.peter.newwindowplz.window-snapshot", qos: .userInitiated)
    private var inFlight = Set<CGWindowID>()
    private var lastRequest: [CGWindowID: CFTimeInterval] = [:]

    func request(windowID: CGWindowID, force: Bool = false) {
        guard ScreenCapturePermission.isGranted else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if !force, let previous = self.lastRequest[windowID], now - previous < 0.45 {
                return
            }
            if self.inFlight.contains(windowID) {
                return
            }

            self.lastRequest[windowID] = now
            self.inFlight.insert(windowID)
            defer { self.inFlight.remove(windowID) }

            guard let image = Self.captureImage(windowID: windowID) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onImage?(windowID, image)
            }
        }
    }

    static func captureImage(windowID: CGWindowID) -> CGImage? {
        guard let source = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let maxWidth: CGFloat = 900
        let scale = min(1, maxWidth / CGFloat(source.width))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
