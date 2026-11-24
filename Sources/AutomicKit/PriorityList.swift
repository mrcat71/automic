import Foundation

/// One ranked device, remembered while it is disconnected.
public struct PriorityEntry: Codable, Hashable, Sendable, Identifiable {
    public var uid: String
    /// The name it had when last connected.
    public var name: String
    public var transport: AudioTransport
    /// Never made the default automatically; it can still be picked by hand.
    public var isDisabled: Bool
    /// When it was last seen connected; nil for entries saved before Automic recorded it.
    public var lastSeen: Date?

    public var id: String { uid }

    public init(uid: String, name: String, transport: AudioTransport = .other, isDisabled: Bool = false, lastSeen: Date? = nil) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.isDisabled = isDisabled
        self.lastSeen = lastSeen
    }
}

/// The ranking of one scope's devices, highest priority first.
public struct PriorityList: Codable, Equatable, Sendable {
    public private(set) var entries: [PriorityEntry]

    public init(entries: [PriorityEntry] = []) {
        self.entries = entries
    }

    /// Adds devices seen for the first time at the bottom, so a new device never takes over
    /// before it is ranked, and refreshes the names and transports of known ones. On the first
    /// merge into an empty list, `current` (the default device at that moment) goes first, so
    /// installing Automic changes nothing until the list is reordered. With `seenAt`, every
    /// merged device is stamped as seen then. Returns whether the list changed.
    @discardableResult
    public mutating func merge(_ devices: [AudioDevice], current: String? = nil, seenAt date: Date? = nil) -> Bool {
        let before = entries
        var incoming = devices
        if entries.isEmpty, let current, let index = incoming.firstIndex(where: { $0.uid == current }) {
            incoming.insert(incoming.remove(at: index), at: 0)
        }
        for device in incoming {
            if let index = entries.firstIndex(where: { $0.uid == device.uid }) {
                entries[index].name = device.name
                entries[index].transport = device.transport
                if let date { entries[index].lastSeen = date }
            } else {
                entries.append(PriorityEntry(uid: device.uid, name: device.name, transport: device.transport, lastSeen: date))
            }
        }
        return entries != before
    }

    /// Reorders only the entries in `visible` (listed in ranking order), as `onMove` offsets
    /// into that subset would; entries left out keep their places. A list that hides some
    /// devices can then reorder the ones it shows.
    public mutating func move(visible: [String], fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let positions = visible.compactMap { uid in entries.firstIndex { $0.uid == uid } }.sorted()
        guard positions.count == visible.count else { return }
        var subset = PriorityList(entries: positions.map { entries[$0] })
        subset.move(fromOffsets: offsets, toOffset: destination)
        for (position, entry) in zip(positions, subset.entries) {
            entries[position] = entry
        }
    }

    /// Moves the entries at `offsets` to before the entry now at `destination`, with the same
    /// meaning as SwiftUI's `onMove`.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { entries.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { entries[$0] }
        let target = destination - valid.count(where: { $0 < destination })
        for index in valid.reversed() {
            entries.remove(at: index)
        }
        entries.insert(contentsOf: moving, at: min(max(target, 0), entries.count))
    }

    /// Moves one entry up (negative) or down (positive) by `steps`, clamped to the list.
    public mutating func move(_ uid: String, by steps: Int) {
        guard let index = entries.firstIndex(where: { $0.uid == uid }) else { return }
        let target = min(max(index + steps, 0), entries.count - 1)
        guard target != index else { return }
        entries.insert(entries.remove(at: index), at: target)
    }

    public mutating func forget(_ uid: String) {
        entries.removeAll { $0.uid == uid }
    }

    public mutating func setDisabled(_ uid: String, _ disabled: Bool) {
        guard let index = entries.firstIndex(where: { $0.uid == uid }) else { return }
        entries[index].isDisabled = disabled
    }

    public func rank(of uid: String) -> Int? {
        entries.firstIndex { $0.uid == uid }
    }

    /// The highest-ranked enabled device among `connected`, or nil when none is.
    public func choose(connected: Set<String>) -> String? {
        entries.first { !$0.isDisabled && connected.contains($0.uid) }?.uid
    }
}
