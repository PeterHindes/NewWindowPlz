import AppKit
import CoreGraphics
import Foundation

@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32

@_silgen_name("SLSCopyManagedDisplaySpaces")
private func SLSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?

struct ManagedSpaceInfo {
    let id: UInt64
    let type: Int
}

struct ManagedDisplayInfo {
    let identifier: String
    let currentSpaceID: UInt64
    let spaces: [ManagedSpaceInfo]
}

enum SpaceMetadata {
    static func displays() -> [ManagedDisplayInfo] {
        let connection = SLSMainConnectionID()
        guard connection != 0,
              let rawDisplays = SLSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return []
        }

        return rawDisplays.compactMap { raw in
            guard let identifier = raw["Display Identifier"] as? String,
                  !identifier.isEmpty,
                  let currentDictionary = raw["Current Space"] as? [String: Any],
                  let currentID = number(currentDictionary["ManagedSpaceID"] ?? currentDictionary["id64"]),
                  let rawSpaces = raw["Spaces"] as? [[String: Any]] else {
                return nil
            }

            let spaces = rawSpaces.compactMap { space -> ManagedSpaceInfo? in
                guard let id = number(space["ManagedSpaceID"] ?? space["id64"]) else {
                    return nil
                }
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                return ManagedSpaceInfo(id: id, type: type)
            }

            return ManagedDisplayInfo(
                identifier: identifier,
                currentSpaceID: currentID,
                spaces: spaces
            )
        }
    }

    static func displayIdentifier(for screen: NSScreen?) -> String? {
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?
                .takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let string = value as? String {
            return UInt64(string)
        }
        return nil
    }
}
