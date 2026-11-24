import Foundation

/// Decides, for one scope, when Automic changes the default device.
///
/// - A device list change or a change to the ranking applies the ranking again.
/// - A default change Automic did not make (Control Center, Sound settings, the Automic menu) is
///   a choice by hand and is kept until the next device list change.
/// - Except shortly after a device list change: macOS itself moves the default to a newly
///   connected device, often a second or two after it appears. Such a change is answered by
///   applying the ranking again, not kept as a choice by hand.
public struct SwitchPolicy: Equatable, Sendable {
    /// How long after a device list change a default change counts as macOS's own follow-up.
    public var settleInterval: TimeInterval

    /// A default chosen by hand is being kept.
    public private(set) var isOverridden = false
    private var lastDeviceChange: Date?
    /// The device Automic asked for and whose default change notification has not arrived yet.
    private var pendingChange: String?

    public init(settleInterval: TimeInterval = 3) {
        self.settleInterval = settleInterval
    }

    /// The set of connected devices changed.
    public mutating func devicesChanged(at date: Date) {
        lastDeviceChange = date
        isOverridden = false
    }

    /// The ranking was edited, or switching was turned back on: the ranking applies again.
    public mutating func rankingChanged() {
        isOverridden = false
    }

    /// The default device changed to `uid`. Returns true when the ranking should be applied again.
    public mutating func defaultChanged(to uid: String?, at date: Date) -> Bool {
        if let pending = pendingChange, pending == uid {
            pendingChange = nil
            return false
        }
        pendingChange = nil
        if let lastDeviceChange, date.timeIntervalSince(lastDeviceChange) < settleInterval {
            return true
        }
        isOverridden = true
        return false
    }

    /// The device to make the default, or nil to leave the current one.
    public mutating func decide(list: PriorityList, connected: Set<String>, current: String?) -> String? {
        guard !isOverridden, let target = list.choose(connected: connected), target != current else { return nil }
        pendingChange = target
        return target
    }

    /// Setting the default that `decide` asked for failed; no notification will come for it.
    public mutating func switchFailed() {
        pendingChange = nil
    }
}
