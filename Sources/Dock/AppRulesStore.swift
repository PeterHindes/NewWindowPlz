import AppKit
import Combine
import Foundation

enum DockClickAction: String, Codable, CaseIterable, Identifiable {
    case moveHere
    case newWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveHere: return "Move Here"
        case .newWindow: return "New Window"
        }
    }

    var detail: String {
        switch self {
        case .moveHere: return "Bring the existing window to this Space"
        case .newWindow: return "Open a new window like before"
        }
    }
}

struct DockAppRule: Codable, Identifiable, Equatable {
    var bundleIdentifier: String
    var displayName: String
    var action: DockClickAction

    var id: String { bundleIdentifier }

    static let seeded: [DockAppRule] = [
        DockAppRule(bundleIdentifier: "com.apple.iCal", displayName: "Calendar", action: .moveHere),
        DockAppRule(bundleIdentifier: "com.apple.ActivityMonitor", displayName: "Activity Monitor", action: .moveHere)
    ]
}

enum DockActionResolver {
    static func resolve(configured: DockClickAction?, inverted: Bool) -> DockClickAction {
        let base = configured ?? .newWindow
        guard inverted else { return base }
        return base == .moveHere ? .newWindow : .moveHere
    }
}

final class AppRulesStore: ObservableObject {
    static let shared = AppRulesStore()

    @Published private(set) var rules: [DockAppRule]

    private let defaults: UserDefaults
    private let rulesKey = "dockClickRules.v1"
    private let initializedKey = "dockClickRules.v1.initialized"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([DockAppRule].self, from: data) {
            rules = decoded
        } else {
            rules = []
        }

        if !defaults.bool(forKey: initializedKey) {
            for seed in DockAppRule.seeded where !rules.contains(where: { $0.id == seed.id }) {
                rules.append(seed)
            }
            defaults.set(true, forKey: initializedKey)
            save()
        }
    }

    var moveHereRules: [DockAppRule] {
        rules.filter { $0.action == .moveHere }
    }

    func rule(for bundleIdentifier: String?) -> DockAppRule? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return rules.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func action(for bundleIdentifier: String?, title: String? = nil) -> DockClickAction? {
        if let rule = rule(for: bundleIdentifier) {
            return rule.action
        }
        if let title, !title.isEmpty {
            return rules.first { $0.id == "name:\(title.lowercased())" }?.action
        }
        return nil
    }

    /// Adds unknown apps with Move Here. Picking an existing rule toggles its
    /// action, which makes the Dock picker useful for flipping an app without
    /// opening Settings.
    @discardableResult
    func toggleOrAdd(bundleIdentifier: String?, title: String) -> (rule: DockAppRule, added: Bool) {
        let key = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey: String
        if let key, !key.isEmpty {
            resolvedKey = key
        } else {
            resolvedKey = "name:\(title.lowercased())"
        }

        if let index = rules.firstIndex(where: { $0.bundleIdentifier == resolvedKey }) {
            var existing = rules[index]
            existing.displayName = title.isEmpty ? existing.displayName : title
            existing.action = existing.action == .moveHere ? .newWindow : .moveHere
            rules[index] = existing
            save()
            return (existing, false)
        }

        let rule = DockAppRule(
            bundleIdentifier: resolvedKey,
            displayName: title.isEmpty ? resolvedKey : title,
            action: .moveHere
        )
        rules.append(rule)
        rules.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        save()
        return (rule, true)
    }

    func setAction(_ action: DockClickAction, for bundleIdentifier: String) {
        guard let index = rules.firstIndex(where: { $0.id == bundleIdentifier }) else { return }
        rules[index].action = action
        save()
    }

    func remove(_ bundleIdentifier: String) {
        rules.removeAll { $0.id == bundleIdentifier }
        save()
    }

    func appIcon(for bundleIdentifier: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: rulesKey)
    }
}
