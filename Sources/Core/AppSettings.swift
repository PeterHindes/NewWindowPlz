import Combine
import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let monitoringEnabled = "monitoringEnabled"
        static let altTabEnabled = "altTabEnabled"
        static let showWindowSnapshots = "showWindowSnapshots"
        static let disableControlClick = "disableControlClick"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    @Published var monitoringEnabled: Bool {
        didSet { defaults.set(monitoringEnabled, forKey: Key.monitoringEnabled) }
    }

    @Published var altTabEnabled: Bool {
        didSet { defaults.set(altTabEnabled, forKey: Key.altTabEnabled) }
    }

    @Published var showWindowSnapshots: Bool {
        didSet { defaults.set(showWindowSnapshots, forKey: Key.showWindowSnapshots) }
    }

    @Published var disableControlClick: Bool {
        didSet { defaults.set(disableControlClick, forKey: Key.disableControlClick) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.monitoringEnabled = defaults.object(forKey: Key.monitoringEnabled) as? Bool ?? true
        self.altTabEnabled = defaults.object(forKey: Key.altTabEnabled) as? Bool ?? true
        self.showWindowSnapshots = defaults.object(forKey: Key.showWindowSnapshots) as? Bool ?? false
        self.disableControlClick = defaults.object(forKey: Key.disableControlClick) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
    }
}
