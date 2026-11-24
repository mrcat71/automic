import AutomicKit
import CoreAudio
import Foundation
import Observation

/// Keeps the default input and output on the highest-ranked connected device.
@Observable
final class DeviceSwitcher {
    static let shared = DeviceSwitcher()

    /// Connected devices per scope, as CoreAudio lists them.
    private(set) var connected: [AudioScope: [AudioDevice]] = [:]
    /// UID of the current default device per scope.
    private(set) var current: [AudioScope: String] = [:]
    private(set) var rankings: [AudioScope: PriorityList] = [:]
    private(set) var policies: [AudioScope: SwitchPolicy] = [:]
    /// Volume of the current default device per scope, 0...1; absent when it has no volume control.
    private(set) var volumes: [AudioScope: Float] = [:]

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var volumeObservations: [AudioScope: PropertyObservation] = [:]
    @ObservationIgnored private var deviceIDs: [String: AudioObjectID] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingDeviceChange = false
    /// Sample data in the settings snapshot: no CoreAudio calls, nothing saved.
    @ObservationIgnored private var isSample = false

    /// Bluetooth devices arrive in bursts, input often after output; one refresh covers a burst.
    private static let debounce = Duration.milliseconds(400)

    init(settings: AppSettings = .shared) {
        self.settings = settings
        for scope in AudioScope.allCases {
            rankings[scope] = settings.ranking(for: scope)
            policies[scope] = SwitchPolicy()
        }
    }

    func start() {
        do {
            try AudioSystem.observeDevices { [weak self] in self?.scheduleRefresh() }
            for scope in AudioScope.allCases {
                try AudioSystem.observeDefault(scope) { [weak self] in self?.defaultDidChange(scope) }
            }
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    // MARK: Queries for the UI

    func ranking(_ scope: AudioScope) -> PriorityList {
        rankings[scope] ?? PriorityList()
    }

    func isConnected(_ uid: String, _ scope: AudioScope) -> Bool {
        connected[scope, default: []].contains { $0.uid == uid }
    }

    func isOverridden(_ scope: AudioScope) -> Bool {
        policies[scope]?.isOverridden ?? false
    }

    /// Connected devices in ranking order.
    func connectedByRank(_ scope: AudioScope) -> [AudioDevice] {
        let ranking = ranking(scope)
        return connected[scope, default: []].sorted {
            (ranking.rank(of: $0.uid) ?? .max) < (ranking.rank(of: $1.uid) ?? .max)
        }
    }

    // MARK: Actions

    /// A pick by hand from the menu: kept until the next device change, like one in Control Center.
    func select(_ uid: String, _ scope: AudioScope) {
        guard !isSample, let id = deviceIDs[uid] else { return }
        do {
            try AudioSystem.setDefaultDevice(scope, to: id)
            Log.audio.notice("Picked \(scope.rawValue, privacy: .public) \(uid, privacy: .public) by hand")
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    func setVolume(_ volume: Float, _ scope: AudioScope) {
        volumes[scope] = volume
        guard !isSample, let uid = current[scope], let id = deviceIDs[uid] else { return }
        do {
            try AudioSystem.setVolume(id, scope, to: volume)
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    func editRanking(_ scope: AudioScope, _ edit: (inout PriorityList) -> Void) {
        var ranking = ranking(scope)
        edit(&ranking)
        guard ranking != rankings[scope] else { return }
        rankings[scope] = ranking
        settings.save(ranking, for: scope)
        policies[scope]?.rankingChanged()
        apply(scope)
    }

    func setAutoSwitch(_ enabled: Bool) {
        settings.autoSwitch = enabled
        guard enabled else { return }
        for scope in AudioScope.allCases {
            policies[scope]?.rankingChanged()
            apply(scope)
        }
    }

    // MARK: Switching

    /// Refreshes after the debounce. `deviceChange` is false for a re-check after macOS moved a
    /// default: that one must not restart the settle window, or Automic and macOS could trade
    /// the default back and forth indefinitely.
    private func scheduleRefresh(deviceChange: Bool = true) {
        pendingDeviceChange = pendingDeviceChange || deviceChange
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            let deviceChange = pendingDeviceChange
            pendingDeviceChange = false
            refresh(deviceChange: deviceChange)
        }
    }

    private func refresh(deviceChange: Bool = true) {
        guard !isSample else { return }
        let devices: [SystemDevice]
        do {
            devices = try AudioSystem.devices()
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
            return
        }
        deviceIDs = Dictionary(devices.map { ($0.device.uid, $0.id) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        for scope in AudioScope.allCases {
            let list = devices.filter { $0.scopes.contains(scope) }.map(\.device)
            connected[scope] = list
            readCurrent(scope)
            var ranking = ranking(scope)
            if ranking.merge(list, current: current[scope], seenAt: now) {
                rankings[scope] = ranking
                settings.save(ranking, for: scope)
            }
            if deviceChange {
                policies[scope]?.devicesChanged(at: now)
            }
            apply(scope)
        }
    }

    private func defaultDidChange(_ scope: AudioScope) {
        readCurrent(scope)
        let reapply = policies[scope]?.defaultChanged(to: current[scope], at: Date()) ?? false
        if reapply {
            // The device list may be stale: a device that is disconnecting often makes macOS
            // move the default before the list change arrives. Decide on a fresh list.
            Log.audio.notice("macOS moved the \(scope.rawValue, privacy: .public) default right after a device change; checking the ranking again")
            scheduleRefresh(deviceChange: false)
        } else if isOverridden(scope) {
            Log.audio.notice("\(scope.rawValue.capitalized, privacy: .public) changed by hand to \(self.current[scope] ?? "none", privacy: .public); kept until the next device change")
        }
    }

    private func readCurrent(_ scope: AudioScope) {
        do {
            let id = try AudioSystem.defaultDevice(scope)
            current[scope] = deviceIDs.first { $0.value == id }?.key
            trackVolume(scope, of: id)
        } catch {
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
            current[scope] = nil
            trackVolume(scope, of: nil)
        }
    }

    /// Follows the volume of the default device, also when the volume keys change it.
    private func trackVolume(_ scope: AudioScope, of id: AudioObjectID?) {
        volumeObservations.removeValue(forKey: scope)?.cancel()
        guard let id else {
            volumes[scope] = nil
            return
        }
        volumes[scope] = AudioSystem.volume(id, scope)
        volumeObservations[scope] = AudioSystem.observeVolume(id, scope) { [weak self] in
            self?.volumes[scope] = AudioSystem.volume(id, scope)
        }
    }

    private func apply(_ scope: AudioScope) {
        guard !isSample, settings.autoSwitch, var policy = policies[scope] else { return }
        defer { policies[scope] = policy }
        let connectedUIDs = Set(connected[scope, default: []].map(\.uid))
        guard let target = policy.decide(list: ranking(scope), connected: connectedUIDs, current: current[scope]) else { return }
        guard let id = deviceIDs[target] else {
            policy.switchFailed()
            return
        }
        do {
            try AudioSystem.setDefaultDevice(scope, to: id)
            Log.audio.notice("Switched \(scope.rawValue, privacy: .public) to \(target, privacy: .public)")
        } catch {
            policy.switchFailed()
            Log.audio.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Sample data

    /// Fills in made-up devices for the settings snapshot and README pictures.
    func loadSample() {
        isSample = true
        settings.persists = false
        let output: [AudioDevice] = [
            AudioDevice(uid: "sample-headset-out", name: "Jabra Evolve2 65", transport: .usb),
            AudioDevice(uid: "sample-airpods-out", name: "AirPods Pro", transport: .bluetooth),
            AudioDevice(uid: "sample-builtin-out", name: "MacBook Pro Speakers", transport: .builtIn),
        ]
        let input: [AudioDevice] = [
            AudioDevice(uid: "sample-headset-in", name: "Jabra Evolve2 65", transport: .usb),
            AudioDevice(uid: "sample-builtin-in", name: "MacBook Pro Microphone", transport: .builtIn),
        ]
        rankings[.output] = PriorityList(entries: [
            PriorityEntry(uid: "sample-headset-out", name: "Jabra Evolve2 65", transport: .usb),
            PriorityEntry(uid: "sample-studio", name: "Studio Display Speakers", transport: .display, lastSeen: Date(timeIntervalSinceNow: -86_400)),
            PriorityEntry(uid: "sample-airpods-out", name: "AirPods Pro", transport: .bluetooth),
            PriorityEntry(uid: "sample-builtin-out", name: "MacBook Pro Speakers", transport: .builtIn),
            PriorityEntry(uid: "sample-teams", name: "Microsoft Teams Audio", transport: .virtual, isDisabled: true),
        ])
        rankings[.input] = PriorityList(entries: [
            PriorityEntry(uid: "sample-yeti", name: "Yeti Stereo Microphone", transport: .usb, lastSeen: Date(timeIntervalSinceNow: -3 * 86_400)),
            PriorityEntry(uid: "sample-headset-in", name: "Jabra Evolve2 65", transport: .usb),
            PriorityEntry(uid: "sample-builtin-in", name: "MacBook Pro Microphone", transport: .builtIn),
        ])
        connected = [.output: output, .input: input]
        current = [.output: "sample-headset-out", .input: "sample-headset-in"]
        volumes = [.output: 0.62, .input: 0.78]
    }
}
