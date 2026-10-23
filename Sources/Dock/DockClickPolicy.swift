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
    /// Shift-click retains the normal Dock behavior, and so do Command and
    /// Option combinations. Control-click is deliberately intercepted: it is
    /// the "do the opposite action" gesture for an app rule.
    static let passThroughModifiers: CGEventFlags = [
        .maskShift, .maskAlternate, .maskCommand
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
