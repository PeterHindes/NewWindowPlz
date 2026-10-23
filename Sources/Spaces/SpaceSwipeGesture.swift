import CoreGraphics
import Darwin
import Foundation

/// Posts the private Dock-swipe gesture sequence used by macOS for trackpad
/// Space switching. The gesture is consumed as a discrete, instant switch, so
/// a multi-Space jump does not animate through every intermediate desktop.
///
/// Technique and macOS 27 event augmentation derived from WhichSpace
/// (https://github.com/gechr/whichspace), MIT licensed.
enum SpaceSwipeGesture {
    private enum Field {
        static let eventType = CGEventField(rawValue: 55)!
        static let gestureHIDType = CGEventField(rawValue: 110)!
        static let gestureSwipeMask = CGEventField(rawValue: 115)!
        static let gestureSwipeMotion = CGEventField(rawValue: 123)!
        static let gestureSwipeProgress = CGEventField(rawValue: 124)!
        static let gestureSwipePositionX = CGEventField(rawValue: 125)!
        static let gestureSwipePositionY = CGEventField(rawValue: 126)!
        static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
        static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
        static let gesturePhase = CGEventField(rawValue: 132)!
        static let gesturePhase2 = CGEventField(rawValue: 134)!
        static let gestureFlavor = CGEventField(rawValue: 138)!
        static let eventTimestamp = CGEventField(rawValue: 169)!
        static let iohidPayload: UInt16 = 4205
    }

    private enum EventType {
        static let dockControl: Int64 = 30
    }

    private enum Phase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
    }

    private static let hidTypeDockSwipe: Int64 = 23
    private static let horizontalMotion: Int64 = 1
    private static let swipeVelocity = 2000.0
    private static let swipeProgress = Double(Float.leastNonzeroMagnitude)

    static var requiresIOHIDPayload: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    /// Returns false if no gesture event could be posted.
    @discardableResult
    static func post(steps: Int, goRight: Bool) -> Bool {
        guard steps > 0 else { return true }
        let velocity = swipeVelocity * Double(max(1, steps))
        for _ in 0..<steps {
            guard postGesture(goRight: goRight, velocity: velocity) else {
                return false
            }
        }
        return true
    }

    private static func postGesture(goRight: Bool, velocity: Double) -> Bool {
        guard requiresIOHIDPayload else {
            return postPlain(phase: Phase.began, goRight: goRight, velocity: velocity)
                && postPlain(phase: Phase.changed, goRight: goRight, velocity: velocity)
                && postPlain(phase: Phase.ended, goRight: goRight, velocity: velocity)
        }

        // Dock applies the Natural scrolling inversion to HID-backed swipes.
        let direction = naturalScrollingEnabled ? goRight : !goRight
        return postAugmented(phase: Phase.began, goRight: direction, velocity: velocity)
            && postAugmented(phase: Phase.changed, goRight: direction, velocity: velocity)
            && postAugmented(phase: Phase.ended, goRight: direction, velocity: velocity)
    }

    private static var naturalScrollingEnabled: Bool {
        let value = CFPreferencesCopyAppValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication
        ) as? NSNumber
        return value?.boolValue ?? true
    }

    private static func postPlain(phase: Int64, goRight: Bool, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        let progress = goRight ? swipeProgress : -swipeProgress
        let signedVelocity = goRight ? velocity : -velocity

        event.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        event.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        event.setIntegerValueField(Field.gesturePhase, value: phase)
        event.setDoubleValueField(Field.gestureSwipeProgress, value: progress)
        event.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        event.setDoubleValueField(Field.gestureSwipeVelocityX, value: signedVelocity)
        event.setDoubleValueField(Field.gestureSwipeVelocityY, value: signedVelocity)
        event.post(tap: .cgSessionEventTap)
        return true
    }

    // MARK: - macOS 27 IOHID payload

    private enum IOHID {
        static let eventTypeVelocity: UInt32 = 9
        static let eventTypeFluidTouchGesture: UInt32 = 23
        static let flavorDockPrimary: UInt16 = 3
    }

    private struct IOHIDEventBase {
        var size: UInt32
        var type: UInt32
        var options: UInt32
        var depth: UInt8
        var reserved: (UInt8, UInt8, UInt8)
    }

    private struct IOHIDFluidTouchGestureData {
        var base: IOHIDEventBase
        var positionX: Int32
        var positionY: Int32
        var positionZ: Int32
        var swipeMask: UInt32
        var gestureMotion: UInt16
        var gestureFlavor: UInt16
        var swipeProgress: Int32
    }

    private struct IOHIDVelocityEventData {
        var base: IOHIDEventBase
        var velocityX: Int32
        var velocityY: Int32
        var velocityZ: Int32
    }

    private struct IOHIDSystemQueueElementHeader {
        var timestamp: UInt64
        var senderID: UInt64
        var options: UInt32
        var attributeLength: UInt32
        var eventCount: UInt32
    }

    private static func postAugmented(phase: Int64, goRight: Bool, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        let progress = goRight ? 1.0 : -1.0
        let signedVelocity = goRight ? velocity : -velocity

        event.setIntegerValueField(Field.eventType, value: EventType.dockControl)
        event.setIntegerValueField(Field.gestureHIDType, value: hidTypeDockSwipe)
        event.setIntegerValueField(Field.gesturePhase, value: phase)
        event.setDoubleValueField(Field.gestureSwipeProgress, value: progress)
        event.setIntegerValueField(Field.gestureSwipeMotion, value: horizontalMotion)
        event.setDoubleValueField(Field.gestureSwipeVelocityX, value: signedVelocity)
        event.setDoubleValueField(Field.gestureSwipeVelocityY, value: 0)
        event.setIntegerValueField(Field.gesturePhase2, value: phase)
        event.setDoubleValueField(Field.gestureFlavor, value: Double(IOHID.flavorDockPrimary))
        event.setDoubleValueField(Field.eventTimestamp, value: Double(mach_absolute_time()))
        event.setDoubleValueField(Field.gestureSwipePositionX, value: 0.1)

        guard let augmented = withIOHIDPayload(event, phase: phase, velocity: signedVelocity) else {
            return false
        }
        augmented.post(tap: .cgSessionEventTap)
        return true
    }

    private static func withIOHIDPayload(_ event: CGEvent, phase: Int64, velocity: Double) -> CGEvent? {
        guard let serialized = event.data else { return nil }
        var bytes = serialized as Data
        guard bytes.starts(with: [0, 0, 0, 2]) else { return nil }
        let payload = iohidPayload(event: event, phase: phase, velocity: velocity)
        let size = UInt16(payload.count)
        bytes.append(UInt8(size >> 8))
        bytes.append(UInt8(size & 0xFF))
        bytes.append(UInt8(Field.iohidPayload >> 8))
        bytes.append(UInt8(Field.iohidPayload & 0xFF))
        bytes.append(payload)
        return CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData)
    }

    private static func iohidPayload(event: CGEvent, phase: Int64, velocity: Double) -> Data {
        let timestamp = event.timestamp != 0 ? event.timestamp : mach_absolute_time()
        let progress = event.getDoubleValueField(Field.gestureSwipeProgress)
        let positionX = event.getDoubleValueField(Field.gestureSwipePositionX)
        let positionY = event.getDoubleValueField(Field.gestureSwipePositionY)
        var data = Data()

        var header = IOHIDSystemQueueElementHeader(
            timestamp: timestamp,
            senderID: 0,
            options: 0,
            attributeLength: 0,
            eventCount: 2
        )
        withUnsafeBytes(of: &header) { data.append(contentsOf: $0) }

        var gesture = IOHIDFluidTouchGestureData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDFluidTouchGestureData>.size),
                type: IOHID.eventTypeFluidTouchGesture,
                options: UInt32((phase & 0xFF) << 24),
                depth: 0,
                reserved: (0, 0, 0)
            ),
            positionX: fixedPoint(positionX),
            positionY: fixedPoint(positionY),
            positionZ: 0,
            swipeMask: 0,
            gestureMotion: UInt16(horizontalMotion),
            gestureFlavor: IOHID.flavorDockPrimary,
            swipeProgress: fixedPoint(-progress)
        )
        withUnsafeBytes(of: &gesture) { data.append(contentsOf: $0) }

        var velocityEvent = IOHIDVelocityEventData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDVelocityEventData>.size),
                type: IOHID.eventTypeVelocity,
                options: 0,
                depth: 1,
                reserved: (0, 0, 0)
            ),
            velocityX: fixedPoint(-velocity),
            velocityY: 0,
            velocityZ: 0
        )
        withUnsafeBytes(of: &velocityEvent) { data.append(contentsOf: $0) }
        return data
    }

    private static func fixedPoint(_ value: Double) -> Int32 {
        let scaled = value * 65_536.0
        if scaled >= Double(Int32.max) { return Int32.max }
        if scaled <= Double(Int32.min) { return Int32.min }
        let fixed = Int32(scaled)
        if fixed == 0, value != 0 {
            return value > 0 ? 1 : -1
        }
        return fixed
    }
}
