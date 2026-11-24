import AutomicKit
import Foundation
import Observation

/// User preferences backed by UserDefaults. The rankings are stored as JSON, one key per scope.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults
    /// Off in the settings snapshot, which shows sample devices that must not overwrite the real lists.
    @ObservationIgnored var persists = true

    /// Automic changes the default devices by itself; off leaves them alone.
    var autoSwitch: Bool {
        didSet { if persists { defaults.set(autoSwitch, forKey: Keys.autoSwitch) } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoSwitch = defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true
    }

    func ranking(for scope: AudioScope) -> PriorityList {
        guard let data = defaults.data(forKey: Keys.ranking(scope)) else { return PriorityList() }
        do {
            return try JSONDecoder().decode(PriorityList.self, from: data)
        } catch {
            Log.app.error("Could not read the \(scope.rawValue, privacy: .public) ranking, starting a new one: \(error.localizedDescription, privacy: .public)")
            return PriorityList()
        }
    }

    func save(_ ranking: PriorityList, for scope: AudioScope) {
        guard persists else { return }
        do {
            try defaults.set(JSONEncoder().encode(ranking), forKey: Keys.ranking(scope))
        } catch {
            Log.app.error("Could not save the \(scope.rawValue, privacy: .public) ranking: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum Keys {
        static let autoSwitch = "autoSwitch"
        static func ranking(_ scope: AudioScope) -> String { "ranking.\(scope.rawValue)" }
    }
}
