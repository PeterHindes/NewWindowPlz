import CoreGraphics

enum DockClickDecision: Equatable {
    case passThrough(DockPassReason)
    case openNewWindow
}

enum DockPassReason: String, Equatable {
    case disabled
    case noTile
    case applicationNotRunning
    case modifierKey
}

struct DockClickPolicy {
    /// The user asked specifically for Shift-click to retain the normal Dock
    /// behavior. Every other shortcut modifier is passed through too so the
    /// app never steals Option/Control/Command Dock gestures.
    static let passThroughModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand
    ]

    func decide(isEnabled: Bool,
                tile: DockTile?,
                modifiers: CGEventFlags) -> DockClickDecision {
        guard isEnabled else { return .passThrough(.disabled) }
        guard let tile else { return .passThrough(.noTile) }
        guard tile.isRunning else { return .passThrough(.applicationNotRunning) }
        if !modifiers.intersection(Self.passThroughModifiers).isEmpty {
            return .passThrough(.modifierKey)
        }
        return .openNewWindow
    }
}
